import SwiftUI
import AppKit
import Sparkle

@main
struct FontManagerApp: App {
    private let helpURL = URL(string: "https://github.com/treyhardin/font-manager")!
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .newItem) {
                Button("Convert a Font…") {
                    conversion.showConvert = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Font Manager Help") {
                    NSWorkspace.shared.open(helpURL)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(helpURL.appendingPathComponent("issues"))
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    fontService.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }
}
