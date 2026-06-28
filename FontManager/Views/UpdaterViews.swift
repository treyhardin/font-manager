import SwiftUI
import Combine
import Sparkle

/// The "Check for Updates…" menu command. Polls Sparkle's main-actor `canCheckForUpdates`
/// via an in-view timer (Swift 6 won't form a KVO key path to that property).
struct CheckForUpdatesView: View {
    let updater: SPUUpdater
    @State private var canCheckForUpdates = true

    private let pollTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!canCheckForUpdates)
        .onReceive(pollTimer) { _ in
            canCheckForUpdates = updater.canCheckForUpdates
        }
    }
}

/// Settings window (⌘,).
struct SettingsView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecks: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecks = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $automaticallyChecks)
                    .onChange(of: automaticallyChecks) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }
                HStack {
                    Button("Check Now…") { updater.checkForUpdates() }
                    Spacer()
                    if let date = updater.lastUpdateCheckDate {
                        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
