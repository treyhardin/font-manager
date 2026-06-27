import Foundation
import AppKit
import UniformTypeIdentifiers

/// Runs export/convert operations off the main thread and drives a single progress toast.
@MainActor
final class ConversionManager: ObservableObject {
    @Published var toast: Toast?

    struct Toast: Identifiable {
        let id = UUID()
        var message: String
        var state: State
        var revealURL: URL?

        enum State {
            case working
            case success
            case failure
        }
    }

    private var dismissTask: Task<Void, Never>?

    // MARK: - Export (outbound "Download as…")

    func download(_ member: FontMember, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FontConversionService.suggestedFilename(for: member, format: format)
        panel.canCreateDirectories = true
        panel.title = "Download Font"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        work("Exporting \(member.styleName)…")
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FontConversionService.export(member, as: format)
                }.value
                let url = destination.pathExtension.isEmpty ? destination.appendingPathExtension(result.ext) : destination
                try result.data.write(to: url)
                success("Saved \(url.lastPathComponent)", reveal: url)
            } catch {
                failure(error.localizedDescription)
            }
        }
    }

    func downloadAll(_ members: [FontMember], family: String, as format: ExportFormat) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export “\(family)” styles into"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        work("Exporting \(members.count) styles…")
        Task {
            var saved = 0
            var failed = 0
            for (index, member) in members.enumerated() {
                self.toast?.message = "Exporting \(index + 1) of \(members.count)…"
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try FontConversionService.export(member, as: format)
                    }.value
                    let name = "\(FontConversionService.baseFilename(for: member)).\(result.ext)"
                    try result.data.write(to: directory.appendingPathComponent(name))
                    saved += 1
                } catch {
                    failed += 1
                }
            }
            if failed == 0 {
                success("Exported \(saved) style\(saved == 1 ? "" : "s")", reveal: directory)
            } else {
                failure("Exported \(saved), \(failed) failed")
            }
        }
    }

    // MARK: - Import (inbound "Convert web font…")

    /// Pick web-font files via an open panel, then convert them.
    func pickAndConvert(into fontService: FontService) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["woff", "woff2", "otf", "ttf"].compactMap { UTType(filenameExtension: $0) }
        panel.title = "Convert Web Font"
        panel.message = "Choose WOFF or WOFF2 files to convert into desktop fonts"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        convert(panel.urls, into: fontService)
    }

    /// Convert web fonts to desktop fonts, save them, then activate + track in the app.
    func convert(_ urls: [URL], into fontService: FontService) {
        guard !urls.isEmpty else { return }

        if urls.count == 1 {
            let source = urls[0]
            work("Converting \(source.lastPathComponent)…")
            Task {
                do {
                    let decoded = try await Task.detached(priority: .userInitiated) {
                        try FontConversionService.webFontToSFNT(source)
                    }.value
                    let ext = decoded.isTrueType ? "ttf" : "otf"

                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent).\(ext)"
                    panel.canCreateDirectories = true
                    panel.title = "Save Converted Font"
                    guard panel.runModal() == .OK, let destination = panel.url else { dismiss(); return }
                    let url = destination.pathExtension.isEmpty ? destination.appendingPathExtension(ext) : destination
                    try decoded.data.write(to: url)
                    fontService.addImportedFont(at: url)
                    success("Converted & activated \(url.lastPathComponent)", reveal: url)
                } catch {
                    failure(error.localizedDescription)
                }
            }
            return
        }

        // Multiple files → one destination folder.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Convert Here"
        panel.message = "Choose a folder for the converted desktop fonts"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        work("Converting \(urls.count) fonts…")
        Task {
            var ok = 0
            var failed = 0
            for (index, source) in urls.enumerated() {
                self.toast?.message = "Converting \(index + 1) of \(urls.count)…"
                do {
                    let decoded = try await Task.detached(priority: .userInitiated) {
                        try FontConversionService.webFontToSFNT(source)
                    }.value
                    let ext = decoded.isTrueType ? "ttf" : "otf"
                    let url = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent).\(ext)")
                    try decoded.data.write(to: url)
                    fontService.addImportedFont(at: url)
                    ok += 1
                } catch {
                    failed += 1
                }
            }
            if failed == 0 {
                success("Converted & activated \(ok) font\(ok == 1 ? "" : "s")", reveal: directory)
            } else {
                failure("Converted \(ok), \(failed) failed")
            }
        }
    }

    // MARK: - Toast state

    private func work(_ message: String) {
        dismissTask?.cancel()
        toast = Toast(message: message, state: .working)
    }

    private func success(_ message: String, reveal: URL?) {
        toast = Toast(message: message, state: .success, revealURL: reveal)
        scheduleDismiss(after: 6)
    }

    private func failure(_ message: String) {
        toast = Toast(message: message, state: .failure)
        scheduleDismiss(after: 8)
    }

    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
