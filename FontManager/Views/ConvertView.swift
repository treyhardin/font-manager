import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Upload a font, detect its format, then download it in any other format.
struct ConvertView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasAcknowledgedFontLicensing") private var licenseAcknowledged = false

    @State private var uploaded: FontConversionService.UploadedFont?
    @State private var isProcessing = false
    @State private var dropTargeted = false
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var pendingTarget: FontConversionService.ConvertTarget?
    @State private var showLicenseAlert = false

    private let acceptedTypes = ["woff", "woff2", "otf", "ttf"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convert Font").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Group {
                if let uploaded {
                    uploadedView(uploaded)
                } else {
                    uploadPrompt
                }
            }
            .padding(20)
        }
        .frame(width: 430)
        .alert("A note on font licensing", isPresented: $showLicenseAlert) {
            Button("Cancel", role: .cancel) { pendingTarget = nil }
            Button("Continue") {
                licenseAcknowledged = true
                if let target = pendingTarget {
                    pendingTarget = nil
                    save(target)
                }
            }
        } message: {
            Text("Converting or exporting a font is your responsibility with respect to that font's license — some commercial and system fonts restrict conversion or redistribution. Use this only for fonts you're permitted to.")
        }
    }

    // MARK: - Upload prompt

    private var uploadPrompt: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [7])
                )
                .background(dropTargeted ? Color.accentColor.opacity(0.06) : .clear)
                .frame(height: 150)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("Drop a font here")
                            .foregroundStyle(.secondary)
                        Text("WOFF · WOFF2 · OTF · TTF")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    handleDrop(providers)
                }

            Button("Choose File…") { chooseFile() }
                .controlSize(.large)

            if isProcessing { ProgressView().controlSize(.small) }
            statusLabel
        }
    }

    // MARK: - Uploaded view

    private func uploadedView(_ uploaded: FontConversionService.UploadedFont) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("UPLOADED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(uploaded.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(uploaded.sourceExtension.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(uploaded.outlineDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Convert \(uploaded.sourceExtension.uppercased()) to")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                let targets = FontConversionService.availableTargets(for: uploaded)
                if targets.isEmpty {
                    Text("No other formats available for this font.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(targets) { target in
                            Button(target.label) { download(target) }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .disabled(isProcessing)
                        }
                    }
                }
            }

            statusLabel

            Button("Choose a different file") {
                self.uploaded = nil
                statusText = nil
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let statusText {
            Label(statusText, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(statusIsError ? .orange : .green)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = acceptedTypes
        panel.title = "Choose a Font"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  ["woff", "woff2", "otf", "ttf"].contains(url.pathExtension.lowercased()) else { return }
            Task { @MainActor in load(url) }
        }
        return true
    }

    private func load(_ url: URL) {
        isProcessing = true
        statusText = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FontConversionService.upload(url)
                }.value
                uploaded = result
            } catch {
                statusText = error.localizedDescription
                statusIsError = true
            }
            isProcessing = false
        }
    }

    private func download(_ target: FontConversionService.ConvertTarget) {
        guard licenseAcknowledged else {
            pendingTarget = target
            showLicenseAlert = true
            return
        }
        save(target)
    }

    private func save(_ target: FontConversionService.ConvertTarget) {
        guard let uploaded else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(uploaded.url.deletingPathExtension().lastPathComponent).\(target.ext)"
        panel.canCreateDirectories = true
        panel.title = "Save Converted Font"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isProcessing = true
        statusText = nil
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let result = try FontConversionService.encode(uploaded, to: target.format)
                    let finalURL = destination.pathExtension.isEmpty ? destination.appendingPathExtension(result.ext) : destination
                    try result.data.write(to: finalURL)
                    return finalURL
                }.value
                statusText = "Saved \(url.lastPathComponent)"
                statusIsError = false
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                statusText = error.localizedDescription
                statusIsError = true
            }
            isProcessing = false
        }
    }
}
