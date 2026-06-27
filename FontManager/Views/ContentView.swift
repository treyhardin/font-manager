import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    @State private var selectedFont: FontItem?
    @State private var isDropTargeted = false

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
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .center) {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay(
                        Label("Drop WOFF / WOFF2 to convert", systemImage: "arrow.down.doc")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    )
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            ConversionToast(manager: conversion)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: conversion.toast?.id)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fontExtensions: Set<String> = ["woff", "woff2", "otf", "ttf"]
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      fontExtensions.contains(url.pathExtension.lowercased()) else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                conversion.convert(urls, into: fontService)
            }
        }
        return true
    }
}
