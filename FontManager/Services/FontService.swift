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

    /// Overrides are keyed by family name (not FontItem.id): Style/Width are intrinsic to
    /// the typeface, so the override survives directory moves and source changes, and
    /// reapplies if the font is re-added.
    private func overrideKey(_ font: FontItem) -> String { font.familyName }

    func effectiveClassification(_ font: FontItem) -> FontClassification {
        overrides[overrideKey(font)]?.classification ?? font.classification
    }

    func effectiveWidth(_ font: FontItem) -> FontWidth {
        overrides[overrideKey(font)]?.width ?? font.width
    }

    func isOverridden(_ font: FontItem) -> Bool {
        !(overrides[overrideKey(font)]?.isEmpty ?? true)
    }

    func isClassificationOverridden(_ font: FontItem) -> Bool {
        overrides[overrideKey(font)]?.classification != nil
    }

    func isWidthOverridden(_ font: FontItem) -> Bool {
        overrides[overrideKey(font)]?.width != nil
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

    private let toast: ToastCenter

    init(toast: ToastCenter) {
        self.toast = toast
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
        overrides[overrideKey(font)] = nil
        saveOverrides()
    }

    func resetClassificationOverride(for font: FontItem) {
        guard var override = overrides[overrideKey(font)] else { return }
        override.classification = nil
        overrides[overrideKey(font)] = override.isEmpty ? nil : override
        saveOverrides()
    }

    func resetWidthOverride(for font: FontItem) {
        guard var override = overrides[overrideKey(font)] else { return }
        override.width = nil
        overrides[overrideKey(font)] = override.isEmpty ? nil : override
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
        for font in fonts { overrides[overrideKey(font)] = nil }
        saveOverrides()
    }

    func setActive(_ active: Bool, for items: [FontItem]) {
        var ok = 0
        var failed = 0
        for font in items {
            let success = active ? activateFont(font, notify: false) : deactivateFont(font, notify: false)
            if success { ok += 1 } else { failed += 1 }
        }
        let verb = active ? "Activated" : "Deactivated"
        if failed == 0 {
            toast.flash("\(verb) \(ok) font\(ok == 1 ? "" : "s")")
        } else {
            toast.flash("\(verb) \(ok), \(failed) failed", isError: true)
        }
    }

    /// Choosing the system value clears the override for that field.
    private func applyClassification(_ classification: FontClassification, to font: FontItem) {
        let key = overrideKey(font)
        var override = overrides[key] ?? FontOverride()
        override.classification = classification == font.classification ? nil : classification
        overrides[key] = override.isEmpty ? nil : override
    }

    private func applyWidth(_ width: FontWidth, to font: FontItem) {
        let key = overrideKey(font)
        var override = overrides[key] ?? FontOverride()
        override.width = width == font.width ? nil : width
        overrides[key] = override.isEmpty ? nil : override
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

        // Migrate old id-based keys ("system:Family", "custom:/dir:Family") to family names.
        var migrated: [String: FontOverride] = [:]
        var didMigrate = false
        for (key, value) in decoded {
            let family: String
            if key.contains(":") {
                family = String(key.split(separator: ":").last ?? Substring(key))
                didMigrate = true
            } else {
                family = key
            }
            if var existing = migrated[family] {
                existing.classification = existing.classification ?? value.classification
                existing.width = existing.width ?? value.width
                migrated[family] = existing
            } else {
                migrated[family] = value
            }
        }
        overrides = migrated
        if didMigrate { saveOverrides() }
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
        // Keyed by (directory, family) so the same family in two folders stays distinct.
        var groups: [String: (family: String, members: [FontMember], directory: String, descriptor: CTFontDescriptor)] = [:]

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

                    let groupKey = "\(directory)\u{0}\(familyName)"
                    if var existing = groups[groupKey] {
                        existing.members.append(member)
                        groups[groupKey] = existing
                    } else {
                        groups[groupKey] = (family: familyName, members: [member], directory: directory, descriptor: descriptor)
                    }
                }
            }
        }

        return groups.values.map { value in
            FontItem(
                familyName: value.family,
                members: value.members,
                isActive: false,
                source: .custom(directory: value.directory),
                classification: FontClassifier.classify(descriptor: value.descriptor, name: value.family),
                width: FontClassifier.width(descriptor: value.descriptor, name: value.family)
            )
        }
    }

    private func loadImportedFonts() -> [FontItem] {
        // Drop tracking for converted files that have since been moved or deleted.
        let livePaths = importedPaths.filter { FileManager.default.fileExists(atPath: $0) }
        if livePaths.count != importedPaths.count {
            importedPaths = livePaths
            UserDefaults.standard.set(importedPaths, forKey: importedKey)
        }

        var membersByFamily: [String: [FontMember]] = [:]
        var descriptorByFamily: [String: CTFontDescriptor] = [:]
        var familyOrder: [String] = []

        for path in importedPaths {
            let url = URL(fileURLWithPath: path)

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

    /// Track + activate converted font files so they appear in the library and persist.
    /// Batched so a multi-file conversion triggers a single reload.
    func addImportedFonts(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls where !importedPaths.contains(url.path) {
            importedPaths.append(url.path)
        }
        UserDefaults.standard.set(importedPaths, forKey: importedKey)
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

    /// Distinct file URLs for a family (a .ttc/.dfont collection shares one URL across faces).
    private func fileURLs(for font: FontItem) -> [URL] {
        var seen = Set<String>()
        return font.members.compactMap { $0.fileURL }.filter { seen.insert($0.path).inserted }
    }

    @discardableResult
    func deactivateFont(_ font: FontItem, notify: Bool = true) -> Bool {
        guard let index = fonts.firstIndex(where: { $0.id == font.id }) else { return false }
        let urls = fileURLs(for: font)
        guard !urls.isEmpty else {
            if notify { toast.flash("“\(font.familyName)” can't be deactivated (no font file).", isError: true) }
            return false
        }

        var failed = false
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerUnregisterFontsForURL(url as CFURL, .user, &error) { failed = true }
        }
        // System fonts can't truly be unregistered; treat as success for the toggle's sake.
        fonts[index].isActive = false
        if notify {
            if failed {
                toast.flash("“\(font.familyName)” couldn't be fully deactivated.", isError: true)
            } else {
                toast.flash("Deactivated “\(font.familyName)”")
            }
        }
        return !failed
    }

    @discardableResult
    func activateFont(_ font: FontItem, notify: Bool = true) -> Bool {
        guard let index = fonts.firstIndex(where: { $0.id == font.id }) else { return false }
        let urls = fileURLs(for: font)
        guard !urls.isEmpty else {
            if notify { toast.flash("“\(font.familyName)” can't be activated (no font file).", isError: true) }
            return false
        }

        var failed = false
        for url in urls {
            var error: Unmanaged<CFError>?
            // Already-registered returns false with an error; that's not a real failure.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .user, &error) {
                if let code = error?.takeRetainedValue(), CFErrorGetCode(code) != 105 /* already registered */ {
                    failed = true
                }
            }
        }
        if failed {
            if notify { toast.flash("“\(font.familyName)” couldn't be activated.", isError: true) }
            return false
        }
        fonts[index].isActive = true
        if notify { toast.flash("Activated “\(font.familyName)”") }
        return true
    }

    func toggleFont(_ font: FontItem) {
        if font.isActive {
            deactivateFont(font)
        } else {
            activateFont(font)
        }
    }
}
