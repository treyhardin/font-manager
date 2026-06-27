import SwiftUI
import CoreText

/// Builds SwiftUI `Font`s for previews — including fonts that aren't activated
/// system-wide, by loading them straight from their file via CoreText.
///
/// `Font.custom(_:size:)` resolves fonts by name, which only works for fonts the
/// OS has registered. Inactive custom fonts aren't registered, so they'd silently
/// fall back to the system font. For those we build a `CTFont` from the file.
@MainActor
enum FontPreview {
    private static var cache: [String: CTFont] = [:]

    static func font(for member: FontMember, size: CGFloat, isActive: Bool) -> Font {
        // Active fonts resolve by name quickly and accurately.
        if isActive {
            return Font.custom(member.postScriptName, size: size)
        }
        if let ctFont = inactiveCTFont(for: member, size: size) {
            return Font(ctFont)
        }
        return Font.custom(member.postScriptName, size: size)
    }

    private static func inactiveCTFont(for member: FontMember, size: CGFloat) -> CTFont? {
        guard let url = member.fileURL else { return nil }

        let key = "\(member.postScriptName)#\(size)"
        if let cached = cache[key] { return cached }

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return nil
        }
        let descriptor = descriptors.first {
            (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == member.postScriptName
        } ?? descriptors.first
        guard let descriptor else { return nil }

        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        cache[key] = ctFont
        return ctFont
    }
}
