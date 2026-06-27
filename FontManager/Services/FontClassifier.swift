import Foundation
import CoreText

/// Derives a `FontClassification` for a font family using, in order of confidence:
/// 1. CoreText symbolic traits (the OS/2 sFamilyClass class mask + monospace bit)
/// 2. the PANOSE bytes of the OS/2 table (set by many fonts that leave sFamilyClass empty)
/// 3. a name-based heuristic
enum FontClassifier {

    /// Classify from a descriptor (preferred — carries the actual file, so it works
    /// for inactive custom fonts and individual `.ttc` faces).
    static func classify(descriptor: CTFontDescriptor, name: String) -> FontClassification {
        if let fromTraits = fromSymbolicTraits(descriptor) { return fromTraits }
        if let fromPanose = fromPanose(descriptor) { return fromPanose }
        return fromName(name)
    }

    /// Classify a system font by name (it resolves because system fonts are registered).
    static func classify(postScriptName: String, name: String) -> FontClassification {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, 0)
        return classify(descriptor: descriptor, name: name)
    }

    // MARK: - Width

    /// Derive a coarse width from `kCTFontWidthTrait` (normalized −1…1, 0 = normal),
    /// falling back to the family name.
    static func width(descriptor: CTFontDescriptor, name: String) -> FontWidth {
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
        if let value = traits?[kCTFontWidthTrait as String] as? Double, value != 0 {
            if value <= -0.06 { return .condensed }
            if value >= 0.06 { return .expanded }
            return .regular
        }
        let lower = name.lowercased()
        if lower.contains("condensed") || lower.contains("narrow") || lower.contains("compress") { return .condensed }
        if lower.contains("expanded") || lower.contains("extended") || lower.contains("wide") { return .expanded }
        return .regular
    }

    static func width(postScriptName: String, name: String) -> FontWidth {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, 0)
        return width(descriptor: descriptor, name: name)
    }

    // MARK: - Sources

    private static func fromSymbolicTraits(_ descriptor: CTFontDescriptor) -> FontClassification? {
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
        let symbolic = (traits?[kCTFontSymbolicTrait as String] as? UInt32) ?? 0

        if symbolic & 0x0000_0400 != 0 { return .monospaced } // kCTFontTraitMonoSpace
        switch symbolic & 0xF000_0000 {                        // kCTFontClassMaskTrait
        case 1 << 28, 2 << 28, 3 << 28, 4 << 28, 7 << 28: return .serif
        case 5 << 28: return .slabSerif
        case 8 << 28: return .sansSerif
        case 9 << 28: return .display
        case 10 << 28: return .script
        case 12 << 28: return .symbol
        default: return nil
        }
    }

    private static func fromPanose(_ descriptor: CTFontDescriptor) -> FontClassification? {
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let osTwo = CTFontTableTag(0x4F53_2F32) // 'OS/2'
        guard let data = CTFontCopyTable(font, osTwo, CTFontTableOptions(rawValue: 0)) as Data?,
              data.count >= 42 else { return nil }
        let bytes = [UInt8](data)
        let familyType = bytes[32]   // PANOSE bFamilyType
        let proportion = bytes[35]   // PANOSE bProportion

        if proportion == 9 { return .monospaced }
        switch familyType {
        case 2:                       // Latin Text
            let serifStyle = bytes[33]
            if (2...10).contains(serifStyle) { return .serif }
            if (11...15).contains(serifStyle) { return .sansSerif }
            return nil
        case 3: return .script        // Latin Hand Written
        case 4: return .display       // Latin Decorative
        case 5: return .symbol        // Latin Symbol
        default: return nil
        }
    }

    private static func fromName(_ name: String) -> FontClassification {
        let lower = name.lowercased()
        if lower.contains("mono") { return .monospaced }
        if lower.contains("slab") { return .slabSerif }
        if lower.contains("sans") || lower.contains("grotesk") || lower.contains("gothic") { return .sansSerif }
        if lower.contains("script") || lower.contains("brush") || lower.contains("hand") { return .script }
        if lower.contains("serif") { return .serif }
        if lower.contains("display") || lower.contains("deco") { return .display }
        return .unclassified
    }
}
