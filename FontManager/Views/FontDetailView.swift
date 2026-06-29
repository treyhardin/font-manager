import SwiftUI
import CoreText

struct FontDetailView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    let font: FontItem
    // AppStorage (not @State tied to the font's identity) so the sample text and size
    // persist as you move between fonts and across launches.
    @AppStorage("preview.text") private var previewText: String = "The quick brown fox jumps over the lazy dog"
    @AppStorage("preview.size") private var previewSize: Double = 32
    // Format / glyph count / file size for the selected family, computed off the main
    // thread when the font changes (not on every slider drag).
    @State private var metadata: String?

    static let samplePangram = "The quick brown fox jumps over the lazy dog"
    static let sampleParagraph = "Sphinx of black quartz, judge my vow. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump!"

    private var classificationBinding: Binding<FontClassification> {
        Binding(
            get: { fontService.effectiveClassification(font) },
            set: { fontService.setClassificationOverride($0, for: font) }
        )
    }

    private var widthBinding: Binding<FontWidth> {
        Binding(
            get: { fontService.effectiveWidth(font) },
            set: { fontService.setWidthOverride($0, for: font) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(font.familyName)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                Picker("Style", selection: classificationBinding) {
                                    ForEach(FontClassification.allCases) { classification in
                                        Text(classification.rawValue).tag(classification)
                                    }
                                }
                                .fixedSize()
                                if fontService.isClassificationOverridden(font) {
                                    RevertButton { fontService.resetClassificationOverride(for: font) }
                                }
                            }

                            HStack(spacing: 3) {
                                Picker("Width", selection: widthBinding) {
                                    ForEach(FontWidth.allCases) { width in
                                        Text(width.rawValue).tag(width)
                                    }
                                }
                                .fixedSize()
                                if fontService.isWidthOverridden(font) {
                                    RevertButton { fontService.resetWidthOverride(for: font) }
                                }
                            }

                            Text(metadataSummary)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if font.members.count > 1 {
                        Menu("Download All") {
                            ForEach(ExportFormat.supported) { format in
                                Button(format.displayName) {
                                    conversion.downloadAll(font.members, family: font.familyName, as: format)
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    // Activate is the affirmative action (prominent accent); deactivating is
                    // reversible and harmless, so it's a plain button rather than a red one.
                    if font.isActive {
                        Button("Deactivate") { fontService.toggleFont(font) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Activate") { fontService.toggleFont(font) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Divider()

                // Preview controls
                HStack {
                    Menu {
                        Button("Pangram") { previewText = Self.samplePangram }
                        Button("Paragraph") { previewText = Self.sampleParagraph }
                        Button("Uppercase") { previewText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
                        Button("Lowercase") { previewText = "abcdefghijklmnopqrstuvwxyz" }
                        Button("Numerals & Symbols") { previewText = "0123456789 & .,;:!?@#$%" }
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Insert sample text")

                    TextField("Preview text", text: $previewText)
                        .textFieldStyle(.roundedBorder)

                    Slider(value: $previewSize, in: 10...120, step: 2) {
                        Text("Size")
                    }
                    .frame(width: 150)

                    Text("\(Int(previewSize))px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40)
                }

                // Font styles preview
                ForEach(font.members) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(member.styleName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Spacer()

                            Menu("Download") {
                                ForEach(ExportFormat.supported) { format in
                                    Button(format.displayName) {
                                        conversion.download(member, as: format)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .font(.caption)
                        }

                        Text(previewText)
                            .font(FontPreview.font(for: member, size: previewSize, isActive: font.isActive))
                            .lineLimit(nil)
                            .textSelection(.enabled)

                        if let url = member.fileURL {
                            Text(url.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }

                        Divider()
                    }
                }

                // Full character set in the family's first style — gives a single-style
                // font something substantial to show and is useful for every family.
                if let first = font.members.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHARACTER SET")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                            Text("abcdefghijklmnopqrstuvwxyz")
                            Text("0123456789 &.,;:!?‘’“”()[]/@#$%*")
                        }
                        .font(FontPreview.font(for: first, size: 24, isActive: font.isActive))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
        .task(id: font.id) {
            let summary = await Task.detached { FontDetailView.metadata(for: font) }.value
            metadata = summary
        }
    }

    /// Style count, plus format / glyph count / file size when available.
    private var metadataSummary: String {
        let styles = "\(font.members.count) style\(font.members.count == 1 ? "" : "s")"
        if let metadata { return "\(styles) · \(metadata)" }
        return styles
    }

    /// Reads format, glyph count and file size for the family's first face. Runs off the
    /// main actor (it parses the font file) so it doesn't stutter the size slider.
    nonisolated private static func metadata(for font: FontItem) -> String? {
        guard let member = font.members.first else { return nil }
        var parts: [String] = []

        if let ext = member.fileURL?.pathExtension.lowercased() {
            switch ext {
            case "otf": parts.append("OpenType")
            case "ttf": parts.append("TrueType")
            case "ttc": parts.append("TrueType Collection")
            case "dfont": parts.append("dfont")
            case "": break
            default: parts.append(ext.uppercased())
            }
        }

        if let ctFont = FontConversionService.ctFont(for: member) {
            let count = CTFontGetGlyphCount(ctFont)
            if count > 0 { parts.append("\(count.formatted()) glyphs") }
        }

        if let size = try? member.fileURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A small revert affordance shown next to an overridden Style/Width picker.
struct RevertButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help("Reset to the value detected on this system")
        .accessibilityLabel("Reset to detected value")
    }
}

/// Detail pane shown when multiple fonts are selected: bulk Style/Width editing
/// (with "Mixed" when they differ), bulk activate/deactivate, and bulk download.
struct MultiFontDetailView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    let fonts: [FontItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(fonts.count) fonts selected")
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 10) {
                            Picker("Style", selection: classificationBinding) {
                                if commonClassification == nil {
                                    Text("Mixed").tag(FontClassification?.none)
                                }
                                ForEach(FontClassification.allCases) { classification in
                                    Text(classification.rawValue).tag(FontClassification?.some(classification))
                                }
                            }
                            .fixedSize()

                            Picker("Width", selection: widthBinding) {
                                if commonWidth == nil {
                                    Text("Mixed").tag(FontWidth?.none)
                                }
                                ForEach(FontWidth.allCases) { width in
                                    Text(width.rawValue).tag(FontWidth?.some(width))
                                }
                            }
                            .fixedSize()

                            if fonts.contains(where: { fontService.isOverridden($0) }) {
                                Button {
                                    fontService.resetOverride(for: fonts)
                                } label: {
                                    Label("Reset", systemImage: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .help("Reset Style and Width for all selected fonts")
                            }
                        }
                    }

                    Spacer()

                    Menu("Download All") {
                        ForEach(ExportFormat.supported) { format in
                            Button(format.displayName) {
                                conversion.downloadMany(fonts, as: format)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button("Activate") { fontService.setActive(true, for: fonts) }
                        .buttonStyle(.borderedProminent)
                    Button("Deactivate") { fontService.setActive(false, for: fonts) }
                        .buttonStyle(.bordered)
                }

                Divider()

                ForEach(fonts) { font in
                    HStack(spacing: 12) {
                        if let member = font.members.first {
                            Text(font.familyName)
                                .font(FontPreview.font(for: member, size: 20, isActive: font.isActive))
                                .lineLimit(1)
                        } else {
                            Text(font.familyName)
                        }

                        Spacer()

                        Text(fontService.effectiveClassification(font).rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ActivationDot(isActive: font.isActive)
                    }
                    Divider()
                }
            }
            .padding(24)
        }
    }

    private var commonClassification: FontClassification? {
        let values = Set(fonts.map { fontService.effectiveClassification($0) })
        return values.count == 1 ? values.first : nil
    }

    private var classificationBinding: Binding<FontClassification?> {
        Binding(
            get: { commonClassification },
            set: { if let value = $0 { fontService.setClassificationOverride(value, for: fonts) } }
        )
    }

    private var commonWidth: FontWidth? {
        let values = Set(fonts.map { fontService.effectiveWidth($0) })
        return values.count == 1 ? values.first : nil
    }

    private var widthBinding: Binding<FontWidth?> {
        Binding(
            get: { commonWidth },
            set: { if let value = $0 { fontService.setWidthOverride(value, for: fonts) } }
        )
    }
}
