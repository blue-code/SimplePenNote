import SwiftUI

@main
struct SimplePenNoteApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if NSClassFromString("XCTestCase") != nil && !DemoData.isEnabled {
                // Unit tests use their own stores and isolated UserDefaults suites.
                // Do not start the user's note store or CloudKit from the test host.
                Color.clear
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
