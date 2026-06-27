import SwiftUI

@main
struct FontManagerApp: App {
    @StateObject private var toastCenter: ToastCenter
    @StateObject private var fontService: FontService
    @StateObject private var conversion: ConversionManager

    init() {
        let toast = ToastCenter()
        _toastCenter = StateObject(wrappedValue: toast)
        _fontService = StateObject(wrappedValue: FontService(toast: toast))
        _conversion = StateObject(wrappedValue: ConversionManager(toast: toast))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fontService)
                .environmentObject(conversion)
                .environmentObject(toastCenter)
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
