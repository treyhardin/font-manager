import SwiftUI
import AppKit

/// A single progress/result toast pinned to the bottom of the window.
struct ConversionToast: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        if let toast = center.toast {
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
                    center.dismiss()
                } label: {
                    PhIcon(.xCircle, size: 15)
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
    private func icon(for state: ToastCenter.Toast.State) -> some View {
        switch state {
        case .working:
            ProgressView()
                .controlSize(.small)
        case .success:
            PhIcon(.checkCircle, size: 16)
                .foregroundStyle(.green)
        case .failure:
            PhIcon(.warning, size: 16)
                .foregroundStyle(.orange)
        }
    }
}
