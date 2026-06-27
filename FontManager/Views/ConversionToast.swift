import SwiftUI
import AppKit

/// A single progress/result toast pinned to the bottom of the window.
struct ConversionToast: View {
    @ObservedObject var manager: ConversionManager

    var body: some View {
        if let toast = manager.toast {
            HStack(spacing: 12) {
                icon(for: toast.state)
                    .frame(width: 18, height: 18)

                Text(toast.message)
                    .font(.callout)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let url = toast.revealURL {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                }

                Button {
                    manager.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }

    @ViewBuilder
    private func icon(for state: ConversionManager.Toast.State) -> some View {
        switch state {
        case .working:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
