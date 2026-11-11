// App Store Connect steps fastlane deliver can't do for SimplePenNote.
// Uses appdesk's authenticated client (APPDESK, default ~/appdesk).
//
//   node scripts/aso/asc_release.mjs status
//   node scripts/aso/asc_release.mjs previews            upload fastlane/previews/<locale>/iphone69_preview.mp4
//   node scripts/aso/asc_release.mjs build <number>      attach a processed build to the version
//   node scripts/aso/asc_release.mjs submit [imageIds…]  one review submission: version + creative images
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const APPDESK = process.env.APPDESK ?? path.join(os.homedir(), 'appdesk');
const { get, getAll, send } = await import(path.join(APPDESK, 'src/asc.js'));
const ROOT = path.resolve(import.meta.dirname, '../..');
const APP_ID = '6762467968';
const LOCALES = ['ko', 'en-US', 'ja', 'zh-Hans'];
const VERSION = fs.readFileSync(path.join(ROOT, 'project.yml'), 'utf8').match(/MARKETING_VERSION:\s*"([^"]+)"/)[1];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function version() {
  const vs = await getAll(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}&fields[appStoreVersions]=versionString,appStoreState`);
  if (!vs.length) throw new Error(`version ${VERSION} not found — run fastlane store_metadata first`);
  return vs[0];
}

async function localizations(v) {
  const locs = await getAll(`/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale&limit=50`);
  return Object.fromEntries(locs.map((l) => [l.attributes.locale, l.id]));
}

async function upload(createPath, type, relName, relType, relId, file, extra = {}) {
  const bytes = fs.readFileSync(file);
  const res = await send('POST', createPath, {
    data: {
      type,
      attributes: { fileName: path.basename(file), fileSize: bytes.length, ...extra },
      relationships: { [relName]: { data: { type: relType, id: relId } } },
    },
  });
  for (const op of res.data.attributes.uploadOperations ?? []) {
    const headers = Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value]));
    const put = await fetch(op.url, { method: op.method ?? 'PUT', headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!put.ok) throw new Error(`upload part ${file}: ${put.status}`);
  }
  const md5 = crypto.createHash('md5').update(bytes).digest('hex');
  await send('PATCH', `${createPath}/${res.data.id}`, {
    data: { type, id: res.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } },
  });
  return res.data.id;
}

async function previews() {
  const v = await version();
  const locs = await localizations(v);
  for (const locale of LOCALES) {
    const file = path.join(ROOT, 'fastlane/previews', locale, 'iphone69_preview.mp4');
    if (!locs[locale]) { console.log(`${locale}: no localization on ${VERSION}`); continue; }
    const sets = (await get(`/v1/appStoreVersionLocalizations/${locs[locale]}/appPreviewSets?include=appPreviews`)).data;
    let set = sets.find((s) => s.attributes.previewType === 'IPHONE_67');
    if (set) {
      for (const p of set.relationships?.appPreviews?.data ?? []) await send('DELETE', `/v1/appPreviews/${p.id}`);
    } else {
      set = (await send('POST', '/v1/appPreviewSets', {
        data: {
          type: 'appPreviewSets', attributes: { previewType: 'IPHONE_67' },
          relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: locs[locale] } } },
        },
      })).data;
    }
    const id = await upload('/v1/appPreviews', 'appPreviews', 'appPreviewSet', 'appPreviewSets', set.id, file,
      { mimeType: 'video/mp4', previewFrameTimeCode: '00:00:05:00' });
    let state;
    for (let i = 0; i < 120; i++) {
      await sleep(5000);
      state = (await get(`/v1/appPreviews/${id}?fields[appPreviews]=assetDeliveryState`)).data.attributes.assetDeliveryState;
      if (['COMPLETE', 'FAILED'].includes(state?.state)) break;
    }
    console.log(`${locale}: preview ${id} ${JSON.stringify(state)}`);
    if (state?.state !== 'COMPLETE') process.exitCode = 1;
  }
}

async function attachBuild(number) {
  const v = await version();
  const builds = (await get(`/v1/builds?filter[app]=${APP_ID}&filter[version]=${number}&filter[preReleaseVersion.version]=${VERSION}&fields[builds]=version,processingState,usesNonExemptEncryption`)).data;
  const b = builds[0];
  if (!b) throw new Error(`build ${number} not found`);
  if (b.attributes.processingState !== 'VALID') throw new Error(`build ${number} is ${b.attributes.processingState}`);
  await send('PATCH', `/v1/appStoreVersions/${v.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
  console.log(`attached build ${number} (${b.id}) to ${VERSION}; usesNonExemptEncryption=${b.attributes.usesNonExemptEncryption}`);
}

async function submit(imageIds) {
  const v = await version();
  const subs = (await get(`/v1/reviewSubmissions?filter[app]=${APP_ID}&filter[platform]=IOS&limit=20`)).data;
  let sub = subs.find((s) => s.attributes.state === 'READY_FOR_REVIEW');
  if (!sub) {
    sub = (await send('POST', '/v1/reviewSubmissions', {
      data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: APP_ID } } } },
    })).data;
  }
  const items = [['appStoreVersion', 'appStoreVersions', v.id], ...imageIds.map((id) => ['appAssetLibraryImage', 'appAssetLibraryImages', id])];
  // Re-runs after a failed submit: skip items the draft already holds.
  const existing = new Set();
  for (const it of (await get(`/v1/reviewSubmissions/${sub.id}/items?include=appStoreVersion,appAssetLibraryImage&limit=50`)).data) {
    for (const rel of Object.values(it.relationships ?? {})) if (rel?.data?.id) existing.add(rel.data.id);
  }
  for (const [rel, type, id] of items) {
    if (existing.has(id)) continue;
    await send('POST', '/v1/reviewSubmissionItems', {
      data: { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } }, [rel]: { data: { type, id } } } },
    });
  }
  const done = await send('PATCH', `/v1/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } });
  console.log(`submitted ${sub.id}: ${done.data.attributes.state} (${items.length} items)`);
}

async function status() {
  const v = await version();
  const locs = await localizations(v);
  console.log(`${VERSION} ${v.attributes.appStoreState} locales=${Object.keys(locs).join(',')}`);
  for (const [locale, id] of Object.entries(locs)) {
    const shots = (await get(`/v1/appStoreVersionLocalizations/${id}/appScreenshotSets?include=appScreenshots`)).data;
    const prevs = (await get(`/v1/appStoreVersionLocalizations/${id}/appPreviewSets?include=appPreviews`)).data;
    const s = shots.map((x) => `${x.attributes.screenshotDisplayType}:${x.relationships?.appScreenshots?.data?.length ?? 0}`).join(' ');
    const p = prevs.map((x) => `${x.attributes.previewType}:${x.relationships?.appPreviews?.data?.length ?? 0}`).join(' ');
    console.log(`  ${locale}: ${s} | previews ${p || '-'}`);
  }
  const build = (await get(`/v1/appStoreVersions/${v.id}/build`)).data;
  console.log(`  build: ${build ? build.attributes.version : 'none'}`);
}

const [cmd, ...rest] = process.argv.slice(2);
await ({ status, previews, build: () => attachBuild(rest[0]), submit: () => submit(rest) }[cmd] ?? (() => { throw new Error('usage'); }))();
