import Foundation
import AppKit
import CoreText

@MainActor
class FontService: ObservableObject {
    @Published var fonts: [FontItem] = []
    @Published var searchText: String = ""
    @Published var customDirectories: [String] = []
    @Published var filterSource: FontSourceFilter = .all

    private let directoriesKey = "customFontDirectories"
    private let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    enum FontSourceFilter: String, CaseIterable {
        case all = "All"
        case system = "System"
        case custom = "Custom"
    }

    var filteredFonts: [FontItem] {
        var result = fonts

        switch filterSource {
        case .all:
            break
        case .system:
            result = result.filter { $0.source == .system }
        case .custom:
            result = result.filter {
                if case .custom = $0.source { return true }
                return false
            }
        }

        if !searchText.isEmpty {
            result = result.filter { font in
                font.familyName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    init() {
        customDirectories = UserDefaults.standard.stringArray(forKey: directoriesKey) ?? []
        loadAllFonts()
    }

    // MARK: - Font loading

    func loadAllFonts() {
        var allFonts: [FontItem] = []
        allFonts.append(contentsOf: loadSystemFonts())
        allFonts.append(contentsOf: loadCustomDirectoryFonts())
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

            return FontItem(familyName: family, members: members, source: .system)
        }
    }

    private func loadCustomDirectoryFonts() -> [FontItem] {
        var fontsByFamily: [String: (members: [FontMember], directory: String)] = [:]

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
                        fontsByFamily[familyName] = (members: [member], directory: directory)
                    }
                }
            }
        }

        return fontsByFamily.map { (family, value) in
            FontItem(
                familyName: family,
                members: value.members,
                isActive: false,
                source: .custom(directory: value.directory)
            )
        }
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
