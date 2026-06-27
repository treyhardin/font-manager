import SwiftUI

struct FontListView: View {
    @EnvironmentObject var fontService: FontService
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
            .padding(8)

            List(fontService.filteredFonts, selection: $selectedFont) { font in
                FontRowView(font: font)
                    .tag(font)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Fonts")
        .toolbar {
            ToolbarItem {
                Text("\(fontService.filteredFonts.count) families")
                    .foregroundStyle(.secondary)
                    .font(.caption)
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

struct FontRowView: View {
    @EnvironmentObject var fontService: FontService
    let font: FontItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(font.familyName)
                    .font(.custom(font.familyName, size: 14))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(font.members.count) style\(font.members.count == 1 ? "" : "s")")
                    if case .custom(let dir) = font.source {
                        Text("·")
                        Text(URL(fileURLWithPath: dir).lastPathComponent)
                            .truncationMode(.head)
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
        }
    }
}
