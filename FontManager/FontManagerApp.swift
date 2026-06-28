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
                Menu("Convert Fonts") {
                    ForEach(ExportFormat.supported) { format in
                        Button("To \(format.displayName)") {
                            conversion.pickAndConvert(to: format, into: fontService)
                        }
                    }
                }
                Button("Convert Fonts to Desktop…") {
                    conversion.pickAndConvert(to: .native, into: fontService)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    fontService.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
