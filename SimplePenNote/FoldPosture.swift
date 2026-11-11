import SwiftUI

/// How the window is split by an active fold (iPhone Duo and other foldables).
///
/// The layout reads the system's `.division` reserved region rather than the device model,
/// screen bounds or orientation, so it follows whatever the hardware reports at that moment.
enum FoldPosture: Equatable {
    /// No active fold — use the normal single-pane layout.
    case flat
    /// Horizontal fold (laptop/tabletop): writing on top, controls on the bottom half.
    case tabletop(fold: CGRect)
    /// Vertical fold (book): note library on one page, canvas on the other.
    case book(fold: CGRect)

    /// The smallest pane that still fits a usable canvas or control block.
    static let minimumPane: CGFloat = 200

    init(proxy: GeometryProxy) {
        guard #available(iOS 27.1, *) else { self = .flat; return }
        let folds = proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        self = Self.classify(folds: folds, in: proxy.size)
    }

    /// Picks a posture from fold rects in the container's local coordinates.
    /// Anything ambiguous (several folds, partial bands, a pane too small) falls back to `.flat`.
    static func classify(folds: [CGRect], in size: CGSize) -> FoldPosture {
        let bounds = CGRect(origin: .zero, size: size)
        guard folds.count == 1, size.width > 0, size.height > 0 else { return .flat }
        let fold = folds[0].intersection(bounds)
        guard !fold.isNull, !fold.isEmpty else { return .flat }

        if fold.width >= size.width * 0.9, fold.height < size.height / 2,
           fold.minY >= minimumPane, size.height - fold.maxY >= minimumPane {
            return .tabletop(fold: fold)
        }
        if fold.height >= size.height * 0.9, fold.width < size.width / 2,
           fold.minX >= minimumPane, size.width - fold.maxX >= minimumPane {
            return .book(fold: fold)
        }
        return .flat
    }
}
