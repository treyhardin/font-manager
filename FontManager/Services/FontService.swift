import Foundation
import AppKit
import CoreText

@MainActor
class FontService: ObservableObject {
    @Published var fonts: [FontItem] = []
    @Published var searchText: String = ""
    @Published var customDirectories: [String] = []
    @Published var filterSource: FontSourceFilter = .all
    @Published var filterClassification: FontClassification?
    @Published var filterWidth: FontWidth?

    private let directoriesKey = "customFontDirectories"
    private let importedKey = "importedFontFiles"
    private let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    /// Paths of individually-converted fonts the app activates on launch.
    private var importedPaths: [String] = []

    enum FontSourceFilter: String, CaseIterable {
        case all = "All"
        case system = "System"
        case custom = "Custom"
    }

    private func matchesSource(_ font: FontItem) -> Bool {
        switch filterSource {
        case .all:
            return true
        case .system:
            return font.source == .system
        case .custom:
            // "Custom" groups everything the user added: directory fonts and imports.
            if case .system = font.source { return false }
            return true
        }
    }

    /// Classifications actually present in the current source filter, in enum order —
    /// drives the filter controls so they never offer an empty bucket.
    var availableClassifications: [FontClassification] {
        let present = Set(fonts.filter(matchesSource).map { $0.classification })
        return FontClassification.allCases.filter { present.contains($0) }
    }

    /// Widths present in the current source filter, in enum order.
    var availableWidths: [FontWidth] {
        let present = Set(fonts.filter(matchesSource).map { $0.width })
        return FontWidth.allCases.filter { present.contains($0) }
    }

    var filteredFonts: [FontItem] {
        var result = fonts.filter(matchesSource)

        if let classification = filterClassification {
            result = result.filter { $0.classification == classification }
        }

        if let width = filterWidth {
            result = result.filter { $0.width == width }
        }

        if !searchText.isEmpty {
            result = result.filter { font in
                font.familyName.localizedCaseInsensitiveContains(searchText)
                    || font.classification.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    init() {
        customDirectories = UserDefaults.standard.stringArray(forKey: directoriesKey) ?? []
        importedPaths = UserDefaults.standard.stringArray(forKey: importedKey) ?? []
        loadAllFonts()
    }

    // MARK: - Font loading

    func loadAllFonts() {
        var allFonts: [FontItem] = []
        allFonts.append(contentsOf: loadSystemFonts())
        allFonts.append(contentsOf: loadCustomDirectoryFonts())
        allFonts.append(contentsOf: loadImportedFonts())
        fonts = allFonts.sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
    }

    private func loadSystemFonts() -> [FontItem] {
        let fontManager = NSFontManager.shared
        let families = fontManager.availableFontFamilies

        return families.map { family in
            let nsMembers = fontManager.availableMembers(ofFontFamily: family) ?? []

            let members = nsMembers.map { memberInfo -> FontMember in
                let postScriptName = memberInfo[0] as? String ?? ""
                let styleName = memberInfo[1] as? String ?? "Regular"
                let weight = memberInfo[2] as? Int ?? 5

                let descriptor = NSFontDescriptor(fontAttributes: [
                    .name: postScriptName
                ])
                let fileURL = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL

                return FontMember(
                    postScriptName: postScriptName,
                    displayName: "\(family) \(styleName)",
                    styleName: styleName,
                    weight: weight,
                    fileURL: fileURL
                )
            }

            let classification = members.first.map {
                FontClassifier.classify(postScriptName: $0.postScriptName, name: family)
            } ?? .unclassified
            let width = members.first.map {
                FontClassifier.width(postScriptName: $0.postScriptName, name: family)
            } ?? .regular

            return FontItem(familyName: family, members: members, source: .system, classification: classification, width: width)
        }
    }

    private func loadCustomDirectoryFonts() -> [FontItem] {
        var fontsByFamily: [String: (members: [FontMember], directory: String, descriptor: CTFontDescriptor)] = [:]

        for directory in customDirectories {
            let dirURL = URL(fileURLWithPath: directory)
            guard let enumerator = FileManager.default.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fontExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as? [CTFontDescriptor] ?? []

                for descriptor in descriptors {
                    let familyName = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? fileURL.deletingPathExtension().lastPathComponent
                    let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? familyName
                    let styleName = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular"

                    let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
                    let weightValue = traits?[kCTFontWeightTrait as String] as? Double ?? 0.0
                    let weight = Int((weightValue + 1.0) * 6.5) // Normalize to ~0-13 range

                    let member = FontMember(
                        postScriptName: postScriptName,
                        displayName: "\(familyName) \(styleName)",
                        styleName: styleName,
                        weight: weight,
                        fileURL: fileURL
                    )

                    if var existing = fontsByFamily[familyName] {
                        existing.members.append(member)
                        fontsByFamily[familyName] = existing
                    } else {
                        fontsByFamily[familyName] = (members: [member], directory: directory, descriptor: descriptor)
                    }
                }
            }
        }

        return fontsByFamily.map { (family, value) in
            FontItem(
                familyName: family,
                members: value.members,
                isActive: false,
                source: .custom(directory: value.directory),
                classification: FontClassifier.classify(descriptor: value.descriptor, name: family),
                width: FontClassifier.width(descriptor: value.descriptor, name: family)
            )
        }
    }

    private func loadImportedFonts() -> [FontItem] {
        var membersByFamily: [String: [FontMember]] = [:]
        var descriptorByFamily: [String: CTFontDescriptor] = [:]
        var familyOrder: [String] = []

        for path in importedPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }

            // Activate so the converted font is usable immediately and across launches.
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .user, &error)

            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                let familyName = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? url.deletingPathExtension().lastPathComponent
                let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? familyName
                let styleName = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular"

                let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
                let weightValue = traits?[kCTFontWeightTrait as String] as? Double ?? 0.0
                let weight = Int((weightValue + 1.0) * 6.5)

                let member = FontMember(
                    postScriptName: postScriptName,
                    displayName: "\(familyName) \(styleName)",
                    styleName: styleName,
                    weight: weight,
                    fileURL: url
                )

                if membersByFamily[familyName] == nil {
                    familyOrder.append(familyName)
                    descriptorByFamily[familyName] = descriptor
                }
                membersByFamily[familyName, default: []].append(member)
            }
        }

        return familyOrder.map { family in
            let classification = descriptorByFamily[family].map {
                FontClassifier.classify(descriptor: $0, name: family)
            } ?? .unclassified
            let width = descriptorByFamily[family].map {
                FontClassifier.width(descriptor: $0, name: family)
            } ?? .regular
            return FontItem(familyName: family, members: membersByFamily[family] ?? [], isActive: true, source: .imported, classification: classification, width: width)
        }
    }

    /// Track + activate a converted font file so it appears in the library and persists.
    func addImportedFont(at url: URL) {
        let path = url.path
        if !importedPaths.contains(path) {
            importedPaths.append(path)
            UserDefaults.standard.set(importedPaths, forKey: importedKey)
        }
        loadAllFonts()
    }

    /// Deactivate and stop tracking an imported font (leaves the file on disk).
    func removeImportedFont(_ font: FontItem) {
        for member in font.members {
            guard let url = member.fileURL else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerUnregisterFontsForURL(url as CFURL, .user, &error)
            importedPaths.removeAll { $0 == url.path }
        }
        UserDefaults.standard.set(importedPaths, forKey: importedKey)
        loadAllFonts()
    }

    // MARK: - Directory management

    func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing font files"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        guard !customDirectories.contains(path) else { return }

        customDirectories.append(path)
        saveDirectories()
        loadAllFonts()
    }

    func removeDirectory(_ path: String) {
        // Deactivate any fonts from this directory first
        for font in fonts {
            if case .custom(let dir) = font.source, dir == path, font.isActive {
                deactivateFont(font)
            }
        }

        customDirectories.removeAll { $0 == path }
        saveDirectories()
        loadAllFonts()
    }

    private func saveDirectories() {
        UserDefaults.standard.set(customDirectories, forKey: directoriesKey)
    }

    // MARK: - Font activation

    func deactivateFont(_ font: FontItem) {
        guard let index = fonts.firstIndex(where: { $0.id == font.id }) else { return }

        for member in font.members {
            guard let url = member.fileURL else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerUnregisterFontsForURL(url as CFURL, .user, &error)
        }

        fonts[index].isActive = false
    }

    func activateFont(_ font: FontItem) {
        guard let index = fonts.firstIndex(where: { $0.id == font.id }) else { return }

        for member in font.members {
            guard let url = member.fileURL else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .user, &error)
        }

        fonts[index].isActive = true
    }

    func toggleFont(_ font: FontItem) {
        if font.isActive {
            deactivateFont(font)
        } else {
            activateFont(font)
        }
    }
}
