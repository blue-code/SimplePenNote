import SwiftUI

enum NotePenColor: String, CaseIterable, Identifiable {
    case ink, red, blue, green, purple

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .ink: return Color(white: 0.1)
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        }
    }
    var label: String {
        switch self {
        case .ink: return String(localized: "검정 펜")
        case .red: return String(localized: "빨간 펜")
        case .blue: return String(localized: "파란 펜")
        case .green: return String(localized: "초록 펜")
        case .purple: return String(localized: "보라 펜")
        }
    }
}

/// Small, local preferences only. Drawings and their cloud records are unchanged.
@MainActor
final class QuickNotePreferences: ObservableObject {
    static let widths: [CGFloat] = [2, 4, 8, 14]
    private let defaults: UserDefaults
    private let persistChanges: Bool

    @Published var penColor: NotePenColor {
        didSet { if persistChanges { defaults.set(penColor.rawValue, forKey: "QuickNote.penColor") } }
    }
    @Published var penWidth: CGFloat {
        didSet { if persistChanges { defaults.set(Double(penWidth), forKey: "QuickNote.penWidth") } }
    }
    @Published var paperStyle: PaperStyle {
        didSet { if persistChanges { defaults.set(paperStyle.rawValue, forKey: "QuickNote.paperStyle") } }
    }

    init(defaults: UserDefaults = .standard, persistChanges: Bool = true) {
        self.defaults = defaults
        self.persistChanges = persistChanges
        penColor = NotePenColor(rawValue: defaults.string(forKey: "QuickNote.penColor") ?? "") ?? .ink
        let width = CGFloat(defaults.double(forKey: "QuickNote.penWidth"))
        penWidth = Self.widths.contains(width) ? width : 4
        paperStyle = PaperStyle(rawValue: defaults.string(forKey: "QuickNote.paperStyle") ?? "") ?? .blank
    }
}
