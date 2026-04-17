import SwiftUI
import PencilKit

enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case blank, grid, lines, cornell, weekly, study
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .blank: return "무지"
        case .grid: return "모눈"
        case .lines: return "줄글"
        case .cornell: return "코넬 노트"
        case .weekly: return "위클리"
        case .study: return "오답 노트"
        }
    }
    
    var icon: String {
        switch self {
        case .blank: return "square"
        case .grid: return "square.grid.3x3"
        case .lines: return "line.horizontal.3"
        case .cornell: return "rectangle.split.2x1"
        case .weekly: return "calendar.badge.clock"
        case .study: return "doc.text.magnifyingglass"
        }
    }
}

class NotePage: Identifiable, ObservableObject, Codable {
    var id = UUID()
    @Published var title: String
    @Published var drawing: PKDrawing
    @Published var paperStyle: PaperStyle
    @Published var date: Date
    
    enum CodingKeys: String, CodingKey {
        case id, title, drawing, paperStyle, date
    }
    
    init(title: String = "새로운 노트", 
         drawing: PKDrawing = PKDrawing(), 
         paperStyle: PaperStyle = .grid, 
         date: Date = Date()) {
        self.title = title
        self.drawing = drawing
        self.paperStyle = paperStyle
        self.date = date
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let drawingData = try container.decode(Data.self, forKey: .drawing)
        drawing = try PKDrawing(data: drawingData)
        paperStyle = try container.decode(PaperStyle.self, forKey: .paperStyle)
        date = try container.decode(Date.self, forKey: .date)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(drawing.dataRepresentation(), forKey: .drawing)
        try container.encode(paperStyle, forKey: .paperStyle)
        try container.encode(date, forKey: .date)
    }
}

class NoteStore: ObservableObject {
    @Published var pages: [NotePage] = []
    @Published var currentPageIndex: Int = 0
    
    private let saveKey = "SimplePenNote_Pages"
    
    init() {
        loadPages()
        if pages.isEmpty {
            pages.append(NotePage(title: "첫 영감", paperStyle: .grid))
        }
        
        // iCloud 동기화 감시
        NotificationCenter.default.addObserver(self, selector: #selector(iCloudDataDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    var currentPage: NotePage {
        if pages.isEmpty {
            let newPage = NotePage()
            pages.append(newPage)
            return newPage
        }
        if currentPageIndex >= pages.count {
            return pages.last!
        }
        return pages[currentPageIndex]
    }
    
    func addNewPage() {
        let newPage = NotePage(title: "노트 \(pages.count + 1)")
        pages.append(newPage)
        currentPageIndex = pages.count - 1
        savePages()
    }
    
    func deletePage(at indexSet: IndexSet) {
        pages.remove(atOffsets: indexSet)
        if pages.isEmpty {
            addNewPage()
        } else if currentPageIndex >= pages.count {
            currentPageIndex = pages.count - 1
        }
        savePages()
    }
    
    func savePages() {
        if let encoded = try? JSONEncoder().encode(pages) {
            // 로컬 저장
            UserDefaults.standard.set(encoded, forKey: saveKey)
            // iCloud 저장 (Key-Value)
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: saveKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
    
    func loadPages() {
        // iCloud 데이터 우선 시도, 없으면 로컬
        let data = NSUbiquitousKeyValueStore.default.data(forKey: saveKey) ?? UserDefaults.standard.data(forKey: saveKey)
        if let data = data, let decoded = try? JSONDecoder().decode([NotePage].self, from: data) {
            self.pages = decoded
        }
    }
    
    @objc func iCloudDataDidChange() {
        DispatchQueue.main.async {
            self.loadPages()
        }
    }
}
