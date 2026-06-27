import SwiftUI

struct DirectoriesView: View {
    @EnvironmentObject var fontService: FontService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Font Directories")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if fontService.customDirectories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No custom directories")
                        .foregroundStyle(.secondary)
                    Text("Add a folder containing font files to browse and activate them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(fontService.customDirectories, id: \.self) { path in
                        DirectoryRow(path: path)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button {
                    fontService.addDirectory()
                } label: {
                    Label("Add Directory", systemImage: "plus")
                }

                Spacer()

                let customCount = fontService.fonts.filter {
                    if case .custom = $0.source { return true }
                    return false
                }.count
                Text("\(customCount) font families from \(fontService.customDirectories.count) directories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 500, height: 350)
    }
}

struct DirectoryRow: View {
    @EnvironmentObject var fontService: FontService
    let path: String

    private var fontCount: Int {
        fontService.fonts.filter {
            if case .custom(let dir) = $0.source { return dir == path }
            return false
        }.count
    }

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .lineLimit(1)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Text("\(fontCount) families")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                fontService.removeDirectory(path)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove directory")
        }
    }
}
