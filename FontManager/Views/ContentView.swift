import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var fontService: FontService
    @EnvironmentObject var conversion: ConversionManager
    @State private var selection: Set<String> = []
    @State private var isDropTargeted = false
    @State private var showingDirectories = false

    /// Resolve the selected ids back to current FontItems (ids are stable across reloads).
    private var selectedFonts: [FontItem] {
        fontService.fonts
            .filter { selection.contains($0.id) }
            .sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            FontListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 264, ideal: 280, max: 360)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedFonts.count {
            case 0:
                Text("Select a font family")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 1:
                FontDetailView(font: selectedFonts[0])
            default:
                MultiFontDetailView(fonts: selectedFonts)
            }
        }
        .frame(minWidth: 820, minHeight: 460)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    conversion.pickAndConvert(into: fontService)
                } label: {
                    Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .labelStyle(.titleAndIcon)
                .help("Convert a web font (WOFF/WOFF2) to a desktop font")

                Button {
                    showingDirectories = true
                } label: {
                    Label("Sources", systemImage: "folder.badge.plus")
                }
                .labelStyle(.titleAndIcon)
                .help("Add or remove custom font folders")
            }
        }
        .toolbarRole(.editor)
        .sheet(isPresented: $showingDirectories) {
            DirectoriesView()
        }
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
