import Foundation
import AppKit
import CoreText

@MainActor
class FontService: ObservableObject {
    @Published var fonts: [FontItem] = []
    @Published var searchText: String = ""
    @Published var customDirectories: [String] = []
    @Published var filterSource: FontSourceFilter = .all
    @Published var filterActivation: ActivationFilter = .all
    @Published var filterClassification: FontClassification?
    @Published var filterWidth: FontWidth?
    /// User Style/Width overrides, keyed by `FontItem.id`. Persisted on-device.
    @Published private(set) var overrides: [String: FontOverride] = [:]

    private let directoriesKey = "customFontDirectories"
    private let importedKey = "importedFontFiles"
    private let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    /// Paths of individually-converted fonts the app activates on launch.
    private var importedPaths: [String] = []

    enum FontSourceFilter: String, CaseIterable {
        case all = "All"
        case system = "System"
        case custom = "Custom"
        case missing = "Missing"
    }

    enum ActivationFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case inactive = "Inactive"
    }

    // MARK: - Effective values (system value unless the user overrode it)

    func effectiveClassification(_ font: FontItem) -> FontClassification {
        overrides[font.id]?.classification ?? font.classification
    }

    func effectiveWidth(_ font: FontItem) -> FontWidth {
        overrides[font.id]?.width ?? font.width
    }

    func isOverridden(_ font: FontItem) -> Bool {
        !(overrides[font.id]?.isEmpty ?? true)
    }

    /// A font still missing a Style after system detection and any override.
    func isMissingInfo(_ font: FontItem) -> Bool {
        effectiveClassification(font) == .unclassified
    }

    private func fontsForCurrentSource() -> [FontItem] {
        switch filterSource {
        case .all:
            return fonts
        case .system:
            return fonts.filter { $0.source == .system }
        case .custom:
            // "Custom" groups everything the user added: directory fonts and imports.
            return fonts.filter {
                if case .system = $0.source { return false }
                return true
            }
        case .missing:
            return fonts.filter(isMissingInfo)
        }
    }

    /// Classifications present in the current source filter (effective values), in enum
    /// order — drives the filter controls so they never offer an empty bucket.
    var availableClassifications: [FontClassification] {
        let present = Set(fontsForCurrentSource().map(effectiveClassification))
        return FontClassification.allCases.filter { present.contains($0) }
    }

    /// Widths present in the current source filter, in enum order.
    var availableWidths: [FontWidth] {
        let present = Set(fontsForCurrentSource().map(effectiveWidth))
        return FontWidth.allCases.filter { present.contains($0) }
    }

    var filteredFonts: [FontItem] {
        var result = fontsForCurrentSource()

        switch filterActivation {
        case .all: break
        case .active: result = result.filter { $0.isActive }
        case .inactive: result = result.filter { !$0.isActive }
        }

        if let classification = filterClassification {
            result = result.filter { effectiveClassification($0) == classification }
        }

        if let width = filterWidth {
            result = result.filter { effectiveWidth($0) == width }
        }

        if !searchText.isEmpty {
            result = result.filter { font in
                font.familyName.localizedCaseInsensitiveContains(searchText)
                    || effectiveClassification(font).rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    init() {
        customDirectories = UserDefaults.standard.stringArray(forKey: directoriesKey) ?? []
        importedPaths = UserDefaults.standard.stringArray(forKey: importedKey) ?? []
        loadOverrides()
        loadAllFonts()
    }

    // MARK: - User overrides

    func setClassificationOverride(_ classification: FontClassification, for font: FontItem) {
        applyClassification(classification, to: font)
        saveOverrides()
    }

    func setWidthOverride(_ width: FontWidth, for font: FontItem) {
        applyWidth(width, to: font)
        saveOverrides()
    }

    func resetOverride(for font: FontItem) {
        overrides[font.id] = nil
        saveOverrides()
    }

    // Bulk variants for multi-selection (one save for the whole batch).

    func setClassificationOverride(_ classification: FontClassification, for fonts: [FontItem]) {
        for font in fonts { applyClassification(classification, to: font) }
        saveOverrides()
    }

    func setWidthOverride(_ width: FontWidth, for fonts: [FontItem]) {
        for font in fonts { applyWidth(width, to: font) }
        saveOverrides()
    }

    func resetOverride(for fonts: [FontItem]) {
        for font in fonts { overrides[font.id] = nil }
        saveOverrides()
    }

    func setActive(_ active: Bool, for fonts: [FontItem]) {
        for font in fonts {
            if active { activateFont(font) } else { deactivateFont(font) }
        }
    }

    /// Choosing the system value clears the override for that field.
    private func applyClassification(_ classification: FontClassification, to font: FontItem) {
        var override = overrides[font.id] ?? FontOverride()
        override.classification = classification == font.classification ? nil : classification
        overrides[font.id] = override.isEmpty ? nil : override
    }

    private func applyWidth(_ width: FontWidth, to font: FontItem) {
        var override = overrides[font.id] ?? FontOverride()
        override.width = width == font.width ? nil : width
        overrides[font.id] = override.isEmpty ? nil : override
    }

    private var overridesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Font Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("overrides.json")
    }

    private func loadOverrides() {
        guard let data = try? Data(contentsOf: overridesURL),
              let decoded = try? JSONDecoder().decode([String: FontOverride].self, from: data) else { return }
        overrides = decoded
    }

    private func saveOverrides() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: overridesURL)
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
