import SwiftUI

@main
struct FontManagerApp: App {
    @StateObject private var fontService = FontService()
    @StateObject private var conversion = ConversionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fontService)
                .environmentObject(conversion)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Convert Web Font…") {
                    conversion.pickAndConvert(into: fontService)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
