# SimplePenNote 수익화 구현

## 제공 가치

기존 비소모성 상품 `com.blueCode.SimplePenNote.pro`를 유지합니다. 구독을 추가하거나 기존 사용자의 구매를 바꾸지 않습니다.

| 기능 | 무료 | Pro 일회 구매 |
| --- | --- | --- |
| 활성 노트 | 5장 | 무제한 |
| 6가지 종이, 색상·굵기, 검색·복제, 앱 잠금 | 제공 | 제공 |
| 개별 PNG/PDF | 워터마크 포함 | 워터마크 없음 |
| 선택한 여러 노트를 하나의 PDF로 | Pro 안내 | 제공 |

일괄 PDF는 진행률을 표시하고 취소를 지원하며, 선택한 내용을 고정하여 페이지별로 생성합니다.

템플릿 미리보기로 첫 노트를 만들고, 제목 검색과 복제로 계속 사용하도록 돕습니다. 구매 화면은 5장 한도, 워터마크 제거, PDF 묶기 각각의 사용 목적을 설명합니다. 무료 내보내기와 닫기 버튼을 유지합니다. 휴지통 복원은 사용자의 기존 기록 회수를 우선하여 무료 한도로 차단하지 않습니다.

## 가격과 스토어

앱은 StoreKit `Product.displayPrice`를 표시합니다. 저장소의 StoreKit 구성 가격은 로컬 테스트용이며 App Store Connect의 실제 가격을 변경하지 않습니다. TestFlight 배포는 `fastlane ios beta`로 수행합니다. 상품 등록·가격 변경·App Store 심사 제출은 별도 작업입니다.

출시 시 App Store Connect에서 다음을 확인합니다.

1. 동일 상품 ID의 비소모성 상품이 판매 가능하며 앱 버전에 연결되어 있는지 확인합니다.
2. 가격, 세금·은행·유료 앱 계약, 판매 지역을 확인합니다.
3. TestFlight/Sandbox에서 실제 구매 시트, 취소, 구매 복원, 앱 재설치 후 권한 복원, 승인 대기, 환불을 검증합니다.
4. 최신 화면으로 스크린샷을 교체합니다. 저장소의 기존 스크린샷은 이전 UI입니다.
5. 앱 버전·빌드 번호를 출시 정책에 맞게 올리고, 아래 테스트와 실기기 Apple Pencil·iCloud 검증을 마친 뒤 제출합니다.

## 검증

```sh
xcodegen generate
xcodebuild -project SimplePenNote.xcodeproj -scheme SimplePenNote \
  -configuration Debug -destination 'platform=iOS Simulator,name=SimplePenNote-RevenueQA' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

유닛 테스트는 PNG 크기·필기 위치, 종이 좌표, PDF 페이지 수와 순서, 일괄 출력 진행률·취소 시 파일 정리, 워터마크, 안전한 파일 경로와 로컬 노트 저장·선택 복원을 검사합니다. UI 테스트는 무료 한도, PDF 묶기 구매 안내, 무료 내보내기에서 Pro 안내로의 전환, 템플릿 갤러리를 검사합니다. 로컬 StoreKit 테스트는 실제 과금 없이 권한 발급·재확인·환불을 검사합니다.

오프라인 편집 대기열과 삭제 대기열을 로컬에 보관하고, 서버의 오래된 내용이 업로드 대기 필기를 덮어쓰지 않도록 합니다. 실제 여러 기기 사이의 iCloud 충돌은 별도 실기기 검증이 필요합니다.

## 2026-11-11 검증 상태

- Debug 앱 및 22개 XCTest/UI 테스트의 빌드가 통과했습니다.
- 서명 없이 실기기용 Release 빌드가 통과했습니다. 배포용 아카이브·서명·업로드 검증과는 별개입니다.
- `scripts/validate-note-model.sh` 실행이 통과했습니다. 실제 모델 코드를 macOS 번들로 컴파일하여 필기·선택 복원, 오래된 클라우드 병합으로부터 편집 보호, 복제, 업로드·삭제 대기열 보존, 삭제된 노트의 재등장 방지, 손상된 클라우드 자산 처리를 검사합니다. 격리된 UserDefaults를 사용하며 실제 iCloud에는 접속하지 않습니다.
- iOS 27.0/27.1 시뮬레이터는 초기 부팅/데이터 마이그레이션이 지연됐고, 재부팅 완료 후에도 서명 유무와 관계없이 XCTest 실행이 시작되지 않아 중단했습니다. UI·PNG/PDF 결과·iOS StoreKit 테스트의 실행 성공을 확인하지 못했습니다.
- 대체 macOS XCTest 환경에서는 StoreKit 테스트 4개가 상품 로딩 시간 초과와 `notEntitled` 오류로 실패했습니다. 구매 성공·복원·환불 검증 완료로 간주하지 않습니다.
- 출시 전 iOS 환경에서 전체 테스트를 실행하고 Sandbox 구매·복원, 실제 여러 기기의 iCloud 및 Apple Pencil을 검증해야 합니다. App Store Connect에서 기존 Pro 상품 `com.blueCode.SimplePenNote.pro`의 `APPROVED` 상태를 확인했습니다. 실제 스토어 가격은 변경하지 않았습니다.

시뮬레이터 없이 저장 모델을 다시 검증하는 명령:

```sh
scripts/validate-note-model.sh
```

## 출시 후 측정

이번 버전은 외부 분석 SDK와 추적을 추가하지 않습니다. App Store Connect에서 확보 가능한 다운로드·매출·Pro 판매량과 사용자 피드백으로 첫 기준선을 만듭니다. 출시 후 같은 기간끼리 Pro 판매량/다운로드, 환불, 크래시, 리뷰를 비교합니다. 화면별 전환율은 이벤트 수집을 구현하지 않았으므로 측정했다고 주장하지 않습니다.

수익 증가를 보장할 수는 없습니다. 먼저 현재 일회 구매 모델에서 사용 가치와 결제 성공률을 검증한 뒤 가격·상품 구성 변경을 결정합니다.

## TestFlight 배포

- 이번 배포 버전: 1.1.0 (12). 업로드 전 기존 최신 빌드 10을 확인했습니다.
- 기존 내부 그룹 `내부`는 모든 빌드 접근 권한을 갖고 있습니다. 외부 테스터 초대나 App Store 심사 제출은 수행하지 않습니다.
- `fastlane ios beta`는 API로 최신 빌드를 조회하고 `project.yml`에 빌드 번호를 반영한 뒤, 기존 유효 프로비저닝 프로파일로 아카이브·업로드하고 Apple 처리를 기다립니다. 조회 실패 시 임의의 번호로 진행하지 않습니다.
- API 키는 기본적으로 `fastlane/AuthKey_33P5W93GJQ.p8`에서 읽고 `ASC_KEY_PATH`로 재정의할 수 있습니다. 키 파일은 Git에서 제외됩니다.
- 이 환경에서는 설치된 Homebrew Fastlane 2.240.1을 사용합니다. 기존 `vendor/bundle`은 Ruby 2.6용이므로 현재 Ruby 4 환경에서는 `bundle exec`로 사용할 수 없습니다.
- iOS 실행 테스트는 TestFlight 설치 후에도 확인해야 합니다. 업로드 성공만으로 결제·필기·공유 동작을 검증한 것으로 간주하지 않습니다.

서명 프로파일은 로컬 배포 인증서 `C599C444…`에 연결된 `com.blueCode.SimplePenNote AppStore C599C444`를 사용합니다. 기존 프로파일의 인증서는 로컬에 없으므로 대체 프로파일을 추가했으며 다른 인증서나 프로파일은 폐기하지 않았습니다.

빌드 11은 업로드 후 Apple 처리 대기 중 필수 API 사용 사유 선언 누락을 발견하여 최종 배포에서 제외했습니다. 빌드 12에는 `PrivacyInfo.xcprivacy`에 앱 전용 UserDefaults 사용 사유 `CA92.1`을 추가했습니다. 적용 근거는 [Apple의 필수 API 사용 사유 규정](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)과 [UserDefaults 승인 사유](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)입니다.
