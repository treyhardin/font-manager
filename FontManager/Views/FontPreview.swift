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
    /// Descriptors are size-independent, so caching by name means changing the preview
    /// size (e.g. dragging the slider) never re-parses the font file.
    private static var descriptorCache: [String: CTFontDescriptor] = [:]

    static func font(for member: FontMember, size: CGFloat, isActive: Bool) -> Font {
        // Active fonts resolve by name quickly and accurately.
        if isActive {
            return Font.custom(member.postScriptName, size: size)
        }
        if let descriptor = descriptor(for: member) {
            return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        }
        return Font.custom(member.postScriptName, size: size)
    }

    private static func descriptor(for member: FontMember) -> CTFontDescriptor? {
        if let cached = descriptorCache[member.postScriptName] { return cached }
        guard let url = member.fileURL,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return nil
        }
        let descriptor = descriptors.first {
            (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == member.postScriptName
        } ?? descriptors.first
        if let descriptor {
            descriptorCache[member.postScriptName] = descriptor
        }
        return descriptor
    }
}
