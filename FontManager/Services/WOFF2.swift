import Foundation

/// Swift wrapper over the WOFF2Kit C shim (Google woff2 + brotli).
enum WOFF2 {

    /// Encode an SFNT (OTF/TTF) into WOFF2.
    static func encode(_ sfnt: Data) throws -> Data {
        guard !sfnt.isEmpty else { throw FontConversionError.invalidWebFont("empty") }
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let rc = sfnt.withUnsafeBytes { raw in
            w2k_sfnt_to_woff2(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &outPtr, &outLen)
        }
        guard rc == 0, let outPtr else { throw FontConversionError.compressionFailed }
        defer { w2k_free(outPtr) }
        return Data(bytes: outPtr, count: outLen)
    }

    /// Decode WOFF2 into an SFNT (OTF/TTF).
    static func decode(_ woff2: Data) throws -> Data {
        guard !woff2.isEmpty else { throw FontConversionError.invalidWebFont("empty") }
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let rc = woff2.withUnsafeBytes { raw in
            w2k_woff2_to_sfnt(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &outPtr, &outLen)
        }
        guard rc == 0, let outPtr else { throw FontConversionError.decompressionFailed }
        defer { w2k_free(outPtr) }
        return Data(bytes: outPtr, count: outLen)
    }
}
