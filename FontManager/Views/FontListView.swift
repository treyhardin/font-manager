import SwiftUI

struct FontListView: View {
    @EnvironmentObject var fontService: FontService
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var styleGlyphSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            // Compact filter header
            VStack(spacing: 8) {
                SidebarSearchField(text: $fontService.searchText, focused: $searchFocused)

                Picker("Source", selection: $fontService.filterSource) {
                    ForEach(FontService.FontSourceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Activation", selection: $fontService.filterActivation) {
                    ForEach(FontService.ActivationFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if fontService.showMissingOnly {
                    // In "Needs Style" mode everything is unclassified, so Style/Width filters don't apply.
                    needsStyleToggle
                } else {
                    FilterSection(title: "Style") {
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
                        FilterSection(title: "Width") {
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

                    if fontService.missingCount > 0 {
                        needsStyleToggle
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

    private var needsStyleToggle: some View {
        Toggle(isOn: $fontService.showMissingOnly) {
            Label("Needs Style (\(fontService.missingCount))", systemImage: "questionmark.circle")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// A titled row of filter buttons that scrolls horizontally if it overflows.
struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    if case .custom(let dir) = font.source {
                        Text("·")
                        Text(URL(fileURLWithPath: dir).lastPathComponent)
                            .truncationMode(.head)
                    }
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
