import SwiftUI

struct FontDetailView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    let font: FontItem
    @State private var previewText: String = "The quick brown fox jumps over the lazy dog"
    @State private var previewSize: Double = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.familyName)
                            .font(.title)
                            .fontWeight(.bold)
                        HStack(spacing: 6) {
                            if font.classification != .unclassified {
                                Text(font.classification.rawValue)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Text("·")
                            }
                            Text("\(font.members.count) style\(font.members.count == 1 ? "" : "s")")
                        }
                        .foregroundStyle(.secondary)
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
