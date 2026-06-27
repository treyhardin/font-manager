import SwiftUI

@main
struct FontManagerApp: App {
    @StateObject private var fontService = FontService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fontService)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
    }
}
