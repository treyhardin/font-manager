import Foundation
import CoreText

/// Member-aware bridge over `FontConversionEngine`: resolves a `FontMember` to its
/// font data and exports it to a chosen format.
enum FontConversionService {

    /// Build a CTFont for a specific member, preferring the on-disk face so that
    /// inactive custom fonts and individual faces of a .ttc resolve correctly.
    static func ctFont(for member: FontMember) -> CTFont? {
        if let url = member.fileURL,
           let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
            for descriptor in descriptors {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                   name == member.postScriptName {
                    return CTFontCreateWithFontDescriptor(descriptor, 0, nil)
                }
            }
        }
        let descriptor = CTFontDescriptorCreateWithNameAndSize(member.postScriptName as CFString, 0)
        return CTFontCreateWithFontDescriptor(descriptor, 0, nil)
    }

    /// The source SFNT for a member: byte-exact copy when it's already a single-face
    /// OTF/TTF file, otherwise a single face assembled from CoreText tables (handles
    /// .ttc/.dfont collections and system fonts).
    static func sourceSFNT(for member: FontMember) throws -> Data {
        if let url = member.fileURL,
           ["otf", "ttf"].contains(url.pathExtension.lowercased()),
           let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           descriptors.count == 1,
           let data = try? Data(contentsOf: url) {
            return data
        }
        guard let font = ctFont(for: member) else { throw FontConversionError.cannotCreateFont }
        return try FontConversionEngine.assembleSFNT(from: font)
    }

    /// Export a member to a given format, returning the bytes and the file extension.
    static func export(_ member: FontMember, as format: ExportFormat) throws -> (data: Data, ext: String) {
        let sfnt = try sourceSFNT(for: member)
        switch format {
        case .native:
            return (sfnt, FontConversionEngine.isTrueType(sfnt) ? "ttf" : "otf")
        case .woff:
            return (try FontConversionEngine.wrapWOFF(sfnt: sfnt), "woff")
        case .woff2:
            return (try WOFF2.encode(sfnt), "woff2")
        }
    }

    /// Decode any web/desktop font file into an installable SFNT, including WOFF2.
    static func webFontToSFNT(_ url: URL) throws -> (data: Data, isTrueType: Bool) {
        let data = try Data(contentsOf: url)
        if data.count >= 4, Array(data.prefix(4)) == Array("wOF2".utf8) {
            let sfnt = try WOFF2.decode(data)
            return (sfnt, FontConversionEngine.isTrueType(sfnt))
        }
        return try FontConversionEngine.webFontToSFNT(url)
    }

    /// A clean default filename (without extension) for a member.
    static func baseFilename(for member: FontMember) -> String {
        let name = member.postScriptName.isEmpty ? member.displayName : member.postScriptName
        return name.replacingOccurrences(of: "/", with: "-")
    }

    /// The desktop extension (otf/ttf) a member would export to, determined cheaply.
    static func nativeExtension(for member: FontMember) -> String {
        if let ext = member.fileURL?.pathExtension.lowercased(), ext == "otf" || ext == "ttf" {
            return ext
        }
        if let font = ctFont(for: member) {
            let glyf = CTFontTableTag(0x676C_7966) // 'glyf'
            if CTFontCopyTable(font, glyf, CTFontTableOptions(rawValue: 0)) != nil { return "ttf" }
        }
        return "otf"
    }

    /// Default filename (with extension) for exporting a member to a format.
    static func suggestedFilename(for member: FontMember, format: ExportFormat) -> String {
        let ext: String
        switch format {
        case .native: ext = nativeExtension(for: member)
        case .woff: ext = "woff"
        case .woff2: ext = "woff2"
        }
        return "\(baseFilename(for: member)).\(ext)"
    }
}
