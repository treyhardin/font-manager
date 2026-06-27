import Foundation
import AppKit

enum FontSource: Hashable {
    case system
    case custom(directory: String)
    case imported
}

enum FontClassification: String, CaseIterable, Identifiable, Hashable {
    case serif = "Serif"
    case sansSerif = "Sans Serif"
    case slabSerif = "Slab Serif"
    case script = "Script"
    case display = "Display"
    case monospaced = "Monospaced"
    case symbol = "Symbol"
    case unclassified = "Unclassified"

    var id: String { rawValue }
}

struct FontItem: Identifiable, Hashable {
    let id: String
    let familyName: String
    let members: [FontMember]
    var isActive: Bool
    let source: FontSource
    let classification: FontClassification

    init(familyName: String, members: [FontMember], isActive: Bool = true, source: FontSource = .system, classification: FontClassification = .unclassified) {
        self.id = Self.makeID(familyName: familyName, source: source)
        self.familyName = familyName
        self.members = members
        self.isActive = isActive
        self.source = source
        self.classification = classification
    }

    /// IDs are namespaced by source so an imported font can share a family name with
    /// a system font without colliding in lists and selection.
    static func makeID(familyName: String, source: FontSource) -> String {
        switch source {
        case .system: return "system:\(familyName)"
        case .custom(let dir): return "custom:\(dir):\(familyName)"
        case .imported: return "imported:\(familyName)"
        }
    }
}

struct FontMember: Identifiable, Hashable {
    let id: String
    let postScriptName: String
    let displayName: String
    let styleName: String
    let weight: Int
    let fileURL: URL?

    init(postScriptName: String, displayName: String, styleName: String, weight: Int, fileURL: URL?) {
        self.id = postScriptName
        self.postScriptName = postScriptName
        self.displayName = displayName
        self.styleName = styleName
        self.weight = weight
        self.fileURL = fileURL
    }
}
