import Foundation
import AppKit

enum FontSource: Hashable, Sendable {
    case system
    case custom(directory: String)
    case imported
}

enum FontClassification: String, CaseIterable, Identifiable, Hashable, Codable {
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

enum FontWidth: String, CaseIterable, Identifiable, Hashable, Codable {
    case condensed = "Condensed"
    case regular = "Regular"
    case expanded = "Expanded"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .condensed: return "arrow.right.and.line.vertical.and.arrow.left"
        case .regular: return "equal"
        case .expanded: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }
}

/// User-defined overrides for a font's Style/Width, stored only in this app.
/// A `nil` field means "use the system-derived value."
struct FontOverride: Codable, Equatable {
    var classification: FontClassification?
    var width: FontWidth?

    var isEmpty: Bool { classification == nil && width == nil }
}

struct FontItem: Identifiable, Hashable, Sendable {
    let id: String
    let familyName: String
    let members: [FontMember]
    var isActive: Bool
    let source: FontSource
    let classification: FontClassification
    let width: FontWidth

    init(familyName: String, members: [FontMember], isActive: Bool = true, source: FontSource = .system, classification: FontClassification = .unclassified, width: FontWidth = .regular) {
        self.id = Self.makeID(familyName: familyName, source: source)
        self.familyName = familyName
        self.members = members
        self.isActive = isActive
        self.source = source
        self.classification = classification
        self.width = width
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

struct FontMember: Identifiable, Hashable, Sendable {
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
