import SwiftUI

struct FontDetailView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    let font: FontItem
    @State private var previewText: String = "The quick brown fox jumps over the lazy dog"
    @State private var previewSize: Double = 32

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

                            Text("\(font.members.count) style\(font.members.count == 1 ? "" : "s")")
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

                    Button(font.isActive ? "Deactivate" : "Activate") {
                        fontService.toggleFont(font)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(font.isActive ? .red : .green)
                }

                Divider()

                // Preview controls
                HStack {
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
            }
            .padding(24)
        }
    }
}

/// A small revert affordance shown next to an overridden Style/Width picker.
struct RevertButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10))
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
                        .tint(.green)
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
                        Circle()
                            .fill(font.isActive ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
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
