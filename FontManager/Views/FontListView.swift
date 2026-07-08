import SwiftUI

struct FontListView: View {
    @EnvironmentObject var fontService: FontService
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var styleGlyphSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            // Compact filter header
            VStack(spacing: 6) {
                SidebarSearchField(text: $fontService.searchText, focused: $searchFocused)

                // Source and status as self-describing dropdowns on one row, so the filter
                // header stays short and the two "All" defaults aren't ambiguous.
                HStack(spacing: 6) {
                    FilterMenuPicker(title: "Source", selection: $fontService.filterSource) { source in
                        fontService.count(for: source)
                    }
                    FilterMenuPicker(title: "Status", selection: $fontService.filterStatus) { status in
                        fontService.count(for: status)
                    }
                    Spacer(minLength: 0)
                    SortMenu(selection: $fontService.sortOrder)
                }

                // Style/Width are unresolved when filtering to "Missing Info", so hide them there.
                if fontService.filterStatus != .missingInfo {
                    FilterSection(title: "Style", activeValue: fontService.filterClassification?.rawValue) {
                        ForEach(fontService.availableClassifications) { classification in
                            FilterIconButton(
                                isOn: fontService.filterClassification == classification,
                                help: classification.rawValue
                            ) {
                                fontService.filterClassification = fontService.filterClassification == classification ? nil : classification
                            } label: {
                                Text(classification == .symbol ? "✻" : "Ag")
                                    .font(styleSpecimenFont(classification, size: styleGlyphSize))
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if fontService.availableWidths.count > 1 {
                        FilterSection(title: "Width", activeValue: fontService.filterWidth?.rawValue) {
                            ForEach(fontService.availableWidths) { width in
                                FilterIconButton(
                                    isOn: fontService.filterWidth == width,
                                    help: width.rawValue
                                ) {
                                    fontService.filterWidth = fontService.filterWidth == width ? nil : width
                                } label: {
                                    Image(systemName: width.symbolName)
                                        .imageScale(.small)
                                }
                            }
                        }
                    }
                }
            }
            .padding(8)

            Divider()

            if fontService.filteredFonts.isEmpty {
                emptyState
            } else {
                List(fontService.filteredFonts, selection: $fontService.selection) { font in
                    FontRowView(font: font)
                }
                .listStyle(.sidebar)
            }

            Divider()
            footer
        }
        .onChange(of: fontService.filterSource) { _, _ in
            // Sub-filters don't carry across source changes (avoids stale empty lists).
            fontService.filterClassification = nil
            fontService.filterWidth = nil
        }
        .onChange(of: fontService.searchFocusToken) { _, _ in
            searchFocused = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No fonts match")
                .foregroundStyle(.secondary)
            if fontService.hasActiveFilters {
                Button("Clear Filters") { fontService.clearFilters() }
                    .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            Text("\(fontService.filteredFonts.count) families")
            Spacer()
            if fontService.hasActiveFilters {
                Button("Clear") { fontService.clearFilters() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

/// A search field styled to sit at the top of the sidebar.
struct SidebarSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            TextField("Search fonts", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// A compact, self-describing dropdown for a sidebar filter (e.g. "Source · All").
/// Replaces stacked segmented controls so the filter header stays short.
struct FilterMenuPicker<T>: View where T: CaseIterable & Hashable & RawRepresentable, T.RawValue == String {
    let title: String
    @Binding var selection: T
    /// Optional count shown after an option in the open menu (e.g. "Missing Info (437)").
    var badge: ((T) -> Int?)? = nil

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { option in
                let label = badge?(option).map { "\(option.rawValue) (\($0))" } ?? option.rawValue
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                Text(selection.rawValue).fontWeight(.medium)
            }
            .font(.callout)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }
}

/// A compact icon menu for choosing the sidebar sort order. Icon-only to stay narrow
/// next to the Source/Status pickers; the open menu checkmarks the active option.
struct SortMenu: View {
    @Binding var selection: FontService.SortOrder

    var body: some View {
        Menu {
            ForEach(FontService.SortOrder.allCases) { order in
                Button {
                    selection = order
                } label: {
                    if order == selection {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help("Sort order")
        .accessibilityLabel("Sort order")
    }
}

/// A titled group of filter buttons that wraps onto multiple rows when it can't fit,
/// so the sidebar never needs horizontal scrolling and content never overflows its width.
/// When a value is selected, the title shows it (e.g. "STYLE · Serif") so the
/// otherwise-unlabeled specimen glyphs are legible once chosen.
struct FilterSection<Content: View>: View {
    let title: String
    var activeValue: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .foregroundStyle(.secondary)
                if let activeValue {
                    Text("· \(activeValue)")
                        .foregroundStyle(.tint)
                }
            }
            .font(.caption2)
            .fontWeight(.semibold)
            FlowLayout(spacing: 6) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-to-right wrapping layout: places children on a row until the next one would
/// overflow the proposed width, then wraps. Keeps filter chips fully visible at any
/// sidebar width without horizontal scrolling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widestRow = max(widestRow, x - spacing)
        }

        let width = maxWidth == .infinity ? widestRow : maxWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A square toggle button used by the Style and Width filters.
struct FilterIconButton<Label: View>: View {
    let isOn: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label

    // Scales the button with the user's text-size preference.
    @ScaledMetric(relativeTo: .body) private var dimension: CGFloat = 29

    var body: some View {
        Button(action: action) {
            label
                .frame(width: dimension, height: dimension)
                .background(
                    isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Activation indicator: filled = active, outlined = inactive (a shape cue, not just color).
struct ActivationDot: View {
    let isActive: Bool

    var body: some View {
        Group {
            if isActive {
                Circle().fill(Color.green)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(isActive ? "Active" : "Inactive")
    }
}

/// A representative typeface for each classification, used as the Style button glyph.
func styleSpecimenFont(_ classification: FontClassification, size: CGFloat) -> Font {
    switch classification {
    case .serif: return .system(size: size, design: .serif).weight(.semibold)
    case .sansSerif: return .system(size: size, design: .default).weight(.semibold)
    case .slabSerif: return .custom("Rockwell", size: size)
    case .script: return .custom("Snell Roundhand", size: size)
    case .display: return .custom("Marker Felt", size: size)
    case .monospaced: return .system(size: size, design: .monospaced).weight(.medium)
    case .symbol, .unclassified: return .system(size: size)
    }
}

struct FontRowView: View {
    @EnvironmentObject var fontService: FontService
    let font: FontItem
    @ScaledMetric(relativeTo: .body) private var previewSize: CGFloat = 14

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(font.familyName)
                    .font(font.members.first.map { FontPreview.font(for: $0, size: previewSize, isActive: font.isActive) } ?? .system(size: previewSize))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    let classification = fontService.effectiveClassification(font)
                    if classification != .unclassified {
                        Text(classification.rawValue)
                        if fontService.isOverridden(font) {
                            Image(systemName: "pencil")
                                .imageScale(.small)
                                .accessibilityLabel("Overridden")
                        }
                        Text("·")
                    }
                    Text("\(font.members.count) style\(font.members.count == 1 ? "" : "s")")
                    if case .imported = font.source {
                        Text("·")
                        Text("Imported")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            ActivationDot(isActive: font.isActive)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(font.isActive ? "Deactivate" : "Activate") {
                fontService.toggleFont(font)
            }
            if case .imported = font.source {
                Divider()
                Button("Remove from Library", role: .destructive) {
                    fontService.removeImportedFont(font)
                }
            }
        }
    }
}
