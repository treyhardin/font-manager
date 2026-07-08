import Foundation
import AppKit
import CoreText

@MainActor
class FontService: ObservableObject {
    @Published var fonts: [FontItem] = []
    @Published var searchText: String = ""
    @Published var customDirectories: [String] = []
    @Published var filterSource: FontSourceFilter = .all
    @Published var filterStatus: StatusFilter = .all
    @Published var filterClassification: FontClassification?
    @Published var filterWidth: FontWidth?
    /// How the sidebar list is ordered. Persisted across launches.
    @Published var sortOrder: SortOrder = .nameAscending {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: sortOrderKey) }
    }
    /// Selected font ids (multi-selection), kept here so filtering can keep selected rows visible.
    @Published var selection: Set<String> = []
    /// Incremented to request the search field take focus (Cmd+F).
    @Published var searchFocusToken = 0
    /// User Style/Width overrides, keyed by `FontItem.id`. Persisted on-device.
    @Published private(set) var overrides: [String: FontOverride] = [:]
    /// True while fonts are being (re)enumerated in the background.
    @Published private(set) var isLoading = false

    private let directoriesKey = "customFontDirectories"
    private let importedKey = "importedFontFiles"
    private let sortOrderKey = "fontSortOrder"
    nonisolated private static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    /// Paths of individually-converted fonts the app activates on launch.
    private var importedPaths: [String] = []

    /// System fonts rarely change, so cache them and only rebuild custom/imported on edits.
    private var cachedSystemItems: [FontItem]?

    /// Lightweight, Sendable system-font metadata gathered on the main thread.
    private struct RawMember: Sendable {
        let postScriptName: String
        let styleName: String
        let weight: Int
    }
    private struct RawFamily: Sendable {
        let family: String
        let members: [RawMember]
    }

    enum FontSourceFilter: String, CaseIterable {
        case all = "All"
        case system = "System"
        case custom = "Custom"
    }

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case inactive = "Inactive"
        case missingInfo = "Missing Info"
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case nameAscending = "Name (A–Z)"
        case nameDescending = "Name (Z–A)"
        case mostRecent = "Most Recent"
        case oldest = "Oldest"
        case mostStyles = "Most Styles"

        var id: String { rawValue }

        /// Sort predicate for two families. Ties (and undated fonts under date sorts) fall
        /// back to A–Z so the order is always stable.
        func areInIncreasingOrder(_ a: FontItem, _ b: FontItem) -> Bool {
            func byName(ascending: Bool = true) -> Bool {
                let result = a.familyName.localizedCaseInsensitiveCompare(b.familyName)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
            switch self {
            case .nameAscending: return byName()
            case .nameDescending: return byName(ascending: false)
            case .mostRecent, .oldest:
                switch (a.dateAdded, b.dateAdded) {
                case let (x?, y?):
                    if x == y { return byName() }
                    return self == .mostRecent ? x > y : x < y
                case (_?, nil): return true   // dated fonts sort ahead of undated ones
                case (nil, _?): return false
                case (nil, nil): return byName()
                }
            case .mostStyles:
                if a.members.count == b.members.count { return byName() }
                return a.members.count > b.members.count
            }
        }
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
        }
    }

    /// Number of fonts still missing a Style (drives the "Missing Info" count).
    var missingCount: Int {
        fonts.filter(isMissingInfo).count
    }

    /// Total families for a source bucket, independent of other filters (for the dropdown count).
    func count(for source: FontSourceFilter) -> Int {
        switch source {
        case .all: return fonts.count
        case .system: return fonts.filter { $0.source == .system }.count
        case .custom: return fonts.filter { if case .system = $0.source { return false }; return true }.count
        }
    }

    /// Total families for a status bucket, independent of other filters (for the dropdown count).
    func count(for status: StatusFilter) -> Int {
        switch status {
        case .all: return fonts.count
        case .active: return fonts.filter { $0.isActive }.count
        case .inactive: return fonts.filter { !$0.isActive }.count
        case .missingInfo: return missingCount
        }
    }

    func selectAllVisible() {
        selection = Set(filteredFonts.map { $0.id })
    }

    func focusSearch() {
        searchFocusToken &+= 1
    }

    /// True when any filter (beyond the default "All" everything) is active.
    var hasActiveFilters: Bool {
        filterSource != .all || filterStatus != .all
            || filterClassification != nil || filterWidth != nil || !searchText.isEmpty
    }

    func clearFilters() {
        filterSource = .all
        filterStatus = .all
        filterClassification = nil
        filterWidth = nil
        searchText = ""
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

        // Already-selected rows stay visible even after they stop matching, so editing a
        // font's Style in "Missing Info" mode doesn't make it vanish out from under you.
        switch filterStatus {
        case .all: break
        case .active: result = result.filter { $0.isActive || selection.contains($0.id) }
        case .inactive: result = result.filter { !$0.isActive || selection.contains($0.id) }
        case .missingInfo: result = result.filter { isMissingInfo($0) || selection.contains($0.id) }
        }

        // Style/Width are unresolved in "Missing Info" mode, so those sub-filters don't apply
        // there; elsewhere they're ignored if their value isn't available (prevents a
        // permanently-empty list when the selected bucket disappears).
        let showingMissing = filterStatus == .missingInfo
        if !showingMissing, let classification = filterClassification, availableClassifications.contains(classification) {
            result = result.filter { effectiveClassification($0) == classification || selection.contains($0.id) }
        }

        if !showingMissing, let width = filterWidth, availableWidths.contains(width) {
            result = result.filter { effectiveWidth($0) == width || selection.contains($0.id) }
        }

        if !searchText.isEmpty {
            result = result.filter { font in
                font.familyName.localizedCaseInsensitiveContains(searchText)
                    || effectiveClassification(font).rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result.sorted(by: sortOrder.areInIncreasingOrder)
    }

    private let toast: ToastCenter

    init(toast: ToastCenter) {
        self.toast = toast
        customDirectories = UserDefaults.standard.stringArray(forKey: directoriesKey) ?? []
        importedPaths = UserDefaults.standard.stringArray(forKey: importedKey) ?? []
        if let raw = UserDefaults.standard.string(forKey: sortOrderKey), let saved = SortOrder(rawValue: raw) {
            sortOrder = saved
        }
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

    /// Full (re)load including system fonts. The heavy CoreText work runs off the main actor.
    func loadAllFonts() {
        let raw = systemRaw()           // cheap NSFontManager pass on the main thread
        cachedSystemItems = nil
        rebuild(systemRaw: raw)
    }

    /// Reload only custom + imported fonts, reusing the cached system fonts.
    func reloadUserFonts() {
        guard cachedSystemItems != nil else { loadAllFonts(); return }
        rebuild(systemRaw: nil)
    }

    private func rebuild(systemRaw raw: [RawFamily]?) {
        let dirs = customDirectories
        let imported = importedPaths
        let cachedSystem = cachedSystemItems
        if cachedSystem == nil && fonts.isEmpty { isLoading = true }

        Task.detached(priority: .userInitiated) {
            let system = cachedSystem ?? FontService.buildSystemItems(raw ?? [])
            let custom = FontService.buildCustomItems(dirs)
            let importedResult = FontService.buildImportedItems(imported)
            let all = (system + custom + importedResult.items)
                .sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cachedSystemItems = system
                if importedResult.livePaths.count != imported.count {
                    self.importedPaths = importedResult.livePaths
                    UserDefaults.standard.set(importedResult.livePaths, forKey: self.importedKey)
                }
                // Preserve activation that was toggled this session across reloads.
                let previous = Dictionary(self.fonts.map { ($0.id, $0.isActive) }, uniquingKeysWith: { first, _ in first })
                self.fonts = all.map { item in
                    guard let wasActive = previous[item.id] else { return item }
                    var copy = item
                    copy.isActive = wasActive
                    return copy
                }
                self.selection.formIntersection(Set(all.map { $0.id }))
                self.isLoading = false
            }
        }
    }

    /// Cheap system-font metadata via NSFontManager (main thread).
    private func systemRaw() -> [RawFamily] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.map { family in
            let members = (manager.availableMembers(ofFontFamily: family) ?? []).map { info in
                RawMember(
                    postScriptName: info[0] as? String ?? "",
                    styleName: info[1] as? String ?? "Regular",
                    weight: info[2] as? Int ?? 5
                )
            }
            return RawFamily(family: family, members: members)
        }
    }

    /// Newest "date added" across a family's files, matching Finder's Date Added where the
    /// volume records it, otherwise creation date. Drives "Recently Added" sorting.
    nonisolated private static func addedDate(for members: [FontMember]) -> Date? {
        let urls = Set(members.compactMap { $0.fileURL })
        var latest: Date?
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            guard let date = values?.addedToDirectoryDate ?? values?.creationDate else { continue }
            if latest == nil || date > latest! { latest = date }
        }
        return latest
    }

    nonisolated private static func buildSystemItems(_ raw: [RawFamily]) -> [FontItem] {
        raw.map { family in
            let members = family.members.map { rawMember -> FontMember in
                let descriptor = CTFontDescriptorCreateWithNameAndSize(rawMember.postScriptName as CFString, 0)
                let fileURL = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
                return FontMember(
                    postScriptName: rawMember.postScriptName,
                    displayName: "\(family.family) \(rawMember.styleName)",
                    styleName: rawMember.styleName,
                    weight: rawMember.weight,
                    fileURL: fileURL
                )
            }
            let classification = members.first.map {
                FontClassifier.classify(postScriptName: $0.postScriptName, name: family.family)
            } ?? .unclassified
            let width = members.first.map {
                FontClassifier.width(postScriptName: $0.postScriptName, name: family.family)
            } ?? .regular
            return FontItem(familyName: family.family, members: members, source: .system, classification: classification, width: width, dateAdded: addedDate(for: members))
        }
    }

    nonisolated private static func buildCustomItems(_ directories: [String]) -> [FontItem] {
        // Keyed by (directory, family) so the same family in two folders stays distinct.
        var groups: [String: (family: String, members: [FontMember], directory: String, descriptor: CTFontDescriptor)] = [:]

        for directory in directories {
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
                width: FontClassifier.width(descriptor: value.descriptor, name: value.family),
                dateAdded: addedDate(for: value.members)
            )
        }
    }

    /// Builds imported-font items and returns the subset of paths that still exist
    /// (the caller prunes dead paths on the main actor).
    nonisolated private static func buildImportedItems(_ paths: [String]) -> (items: [FontItem], livePaths: [String]) {
        let livePaths = paths.filter { FileManager.default.fileExists(atPath: $0) }

        var membersByFamily: [String: [FontMember]] = [:]
        var descriptorByFamily: [String: CTFontDescriptor] = [:]
        var familyOrder: [String] = []

        for path in livePaths {
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

        let items = familyOrder.map { family -> FontItem in
            let classification = descriptorByFamily[family].map {
                FontClassifier.classify(descriptor: $0, name: family)
            } ?? .unclassified
            let width = descriptorByFamily[family].map {
                FontClassifier.width(descriptor: $0, name: family)
            } ?? .regular
            let members = membersByFamily[family] ?? []
            return FontItem(familyName: family, members: members, isActive: true, source: .imported, classification: classification, width: width, dateAdded: addedDate(for: members))
        }
        return (items, livePaths)
    }

    /// Track + activate converted font files so they appear in the library and persist.
    /// Batched so a multi-file conversion triggers a single reload.
    func addImportedFonts(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls where !importedPaths.contains(url.path) {
            importedPaths.append(url.path)
        }
        UserDefaults.standard.set(importedPaths, forKey: importedKey)
        reloadUserFonts()
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
        reloadUserFonts()
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
        reloadUserFonts()
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
        reloadUserFonts()
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
