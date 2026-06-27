import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fontService: FontService
    @State private var selectedFont: FontItem?

    var body: some View {
        NavigationSplitView {
            FontListView(selectedFont: $selectedFont)
        } detail: {
            if let font = selectedFont {
                FontDetailView(font: font)
            } else {
                Text("Select a font family")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $fontService.searchText, prompt: "Search fonts")
        .frame(minWidth: 700, minHeight: 400)
    }
}
