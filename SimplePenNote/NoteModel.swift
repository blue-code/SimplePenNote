import SwiftUI
import PencilKit
import Combine

class NotePage: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var drawing: PKDrawing
    @Published var date: Date
    
    init(title: String = "Untitled", drawing: PKDrawing = PKDrawing(), date: Date = Date()) {
        self.title = title
        self.drawing = drawing
        self.date = date
    }
}

class NoteStore: ObservableObject {
    @Published var pages: [NotePage] = []
    @Published var currentPageIndex: Int = 0
    
    init() {
        // Initial page
        let initialPage = NotePage(title: "첫 번째 노트")
        pages.append(initialPage)
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
