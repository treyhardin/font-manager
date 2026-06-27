import SwiftUI

struct FontListView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    @Binding var selectedFont: FontItem?
    @State private var showingDirectories = false

    var body: some View {
        VStack(spacing: 0) {
            // Source filter
            Picker("Source", selection: $fontService.filterSource) {
                ForEach(FontService.FontSourceFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Style / Width filters hide in "Missing" mode (everything there is unclassified).
            if fontService.filterSource != .missing {
                // Style filter — icon buttons
                FilterSection(title: "Style") {
                    ForEach(fontService.availableClassifications) { classification in
                        FilterIconButton(
                            isOn: fontService.filterClassification == classification,
                            help: classification.rawValue
                        ) {
                            fontService.filterClassification = fontService.filterClassification == classification ? nil : classification
                        } label: {
                            Text(classification == .symbol ? "✻" : "Ag")
                                .font(styleSpecimenFont(classification, size: 15))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                    }
                }

                // Width filter — icon buttons (only when there's more than one width)
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
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 8)

            List(fontService.filteredFonts, selection: $selectedFont) { font in
                FontRowView(font: font)
                    .tag(font)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Fonts")
        .onChange(of: fontService.filterSource) { _, _ in
            // Sub-filters don't carry across source changes (avoids stale empty lists).
            fontService.filterClassification = nil
            fontService.filterWidth = nil
        }
        .toolbar {
            ToolbarItem {
                Text("\(fontService.filteredFonts.count) families")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            ToolbarItem {
                Button {
                    conversion.pickAndConvert(into: fontService)
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .help("Convert a web font (WOFF/WOFF2) to a desktop font")
            }
            ToolbarItem {
                Button {
                    showingDirectories = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Manage font directories")
            }
        }
        .sheet(isPresented: $showingDirectories) {
            DirectoriesView()
        }
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
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
}

/// A square toggle button used by the Style and Width filters.
struct FilterIconButton<Label: View>: View {
    let isOn: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 30, height: 28)
                .background(
                    isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(font.familyName)
                    .font(font.members.first.map { FontPreview.font(for: $0, size: 14, isActive: font.isActive) } ?? .system(size: 14))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    let classification = fontService.effectiveClassification(font)
                    if classification != .unclassified {
                        Text(classification.rawValue)
                        if fontService.isOverridden(font) {
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
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

            Circle()
                .fill(font.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
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
