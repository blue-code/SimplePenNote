import SwiftUI
import PencilKit

enum PaperStyle: String, CaseIterable, Identifiable {
    case blank, grid, lines
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .blank: return "square"
        case .grid: return "square.grid.3x3"
        case .lines: return "line.horizontal.3"
        }
    }
}

class NotePage: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var drawing: PKDrawing
    @Published var paperStyle: PaperStyle
    @Published var date: Date
    
    init(title: String = "새로운 노트", 
         drawing: PKDrawing = PKDrawing(), 
         paperStyle: PaperStyle = .grid, 
         date: Date = Date()) {
        self.title = title
        self.drawing = drawing
        self.paperStyle = paperStyle
        self.date = date
    }
}

class NoteStore: ObservableObject {
    @Published var pages: [NotePage] = []
    @Published var currentPageIndex: Int = 0
    
    init() {
        pages.append(NotePage(title: "첫 영감", paperStyle: .grid))
    }
    
    var currentPage: NotePage {
        if pages.isEmpty {
            let newPage = NotePage()
            pages.append(newPage)
            return newPage
        }
        return pages[currentPageIndex]
    }
    
    func addNewPage() {
        let newPage = NotePage(title: "노트 \(pages.count + 1)")
        pages.append(newPage)
        currentPageIndex = pages.count - 1
    }
    
    func deletePage(at indexSet: IndexSet) {
        pages.remove(atOffsets: indexSet)
        if pages.isEmpty {
            addNewPage()
        } else if currentPageIndex >= pages.count {
            currentPageIndex = pages.count - 1
        }
    }
}
