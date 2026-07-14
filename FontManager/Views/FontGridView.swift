import SwiftUI

/// The default detail view when nothing is selected: a browsable grid of the same fonts
/// shown in the sidebar (filters applied), rendered as specimen cards. Clicking a card
/// selects that family and switches to the detail view.
struct FontGridView: View {
    @EnvironmentObject var fontService: FontService
    /// Custom specimen text; blank shows each family's name. Persisted, separate from the
    /// detail view's own sample text so the grid keeps its font-name default.
    @AppStorage("grid.previewText") private var previewText: String = ""
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            previewInput
            Divider()
            if fontService.filteredFonts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(fontService.filteredFonts) { font in
                            FontCardView(font: font, previewText: previewText)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var previewInput: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
            TextField("Preview text — leave blank to show font names", text: $previewText)
                .textFieldStyle(.plain)
                .onExitCommand { previewText = "" }
            if !previewText.isEmpty {
                Button {
                    previewText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear preview text")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: fontService.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "textformat")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(fontService.hasActiveFilters ? "No fonts match your filters" : "No fonts found")
                .font(.title3)
                .foregroundStyle(.secondary)
            if fontService.hasActiveFilters {
                Button("Clear Filters") { fontService.clearFilters() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A "‹ All Fonts" control shown atop a detail view; clears the selection to return to
/// the grid. Also bound to ⌘[ so there's always a way back.
struct BackToGridButton: View {
    @EnvironmentObject var fontService: FontService

    var body: some View {
        Button {
            fontService.selection = []
        } label: {
            Label("All Fonts", systemImage: "chevron.backward")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Back to all fonts")
        .keyboardShortcut("[", modifiers: .command)
    }
}

/// A specimen card: the family name set in its own typeface, with a metadata caption and
/// activation indicator. The whole card is a button that selects the family.
struct FontCardView: View {
    @EnvironmentObject var fontService: FontService
    let font: FontItem
    var previewText: String = ""
    @State private var hovering = false
    @ScaledMetric(relativeTo: .title2) private var specimenSize: CGFloat = 30

    var body: some View {
        Button {
            fontService.selection = [font.id]
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(previewText.isEmpty ? font.familyName : previewText)
                    .font(font.members.first.map { FontPreview.font(for: $0, size: specimenSize, isActive: font.isActive) } ?? .system(size: specimenSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)

                HStack(spacing: 4) {
                    // Always name the font — the specimen above may show custom preview text.
                    Text(font.familyName)
                    if let foundry = font.foundry {
                        Text("·")
                        Text(foundry)
                    }
                    Text("·")
                    Text("\(font.members.count) style\(font.members.count == 1 ? "" : "s")")
                    Spacer(minLength: 4)
                    ActivationDot(isActive: font.isActive)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hovering ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: hovering ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show \(font.familyName)")
    }
}
