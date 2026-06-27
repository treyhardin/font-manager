import Foundation
import AppKit

enum FontSource: Hashable {
    case system
    case custom(directory: String)
}

struct FontItem: Identifiable, Hashable {
    let id: String
    let familyName: String
    let members: [FontMember]
    var isActive: Bool
    let source: FontSource

    init(familyName: String, members: [FontMember], isActive: Bool = true, source: FontSource = .system) {
        self.id = familyName
        self.familyName = familyName
        self.members = members
        self.isActive = isActive
        self.source = source
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
