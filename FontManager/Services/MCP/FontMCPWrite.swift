import Foundation
import MCP

/// Write path for the MCP server: applies foundry/classification/width overrides through
/// `FontService` (so changes persist to `overrides.json` and update the app UI live).
///
/// Runs on the main actor because it mutates `FontService`. Gated by the caller behind the
/// `mcp.allowWrites` setting. Default policy fills gaps only and never overwrites an
/// existing value unless `force` is set — see `apply`.
@MainActor
enum FontMCPWrite {

    private struct Skip: Codable { let field: String; let reason: String }
    private struct Effective: Codable { let foundry: String?; let classification: String; let width: String }
    private struct UpdateResult: Codable {
        let family: String
        var applied: [String]
        var skipped: [Skip]
        var error: String?
        var effective: Effective?
    }
    private struct Payload: Codable { let results: [UpdateResult] }

    /// Apply a batch of per-family attribute edits.
    /// - Parameters:
    ///   - updates: array of objects `{ family, foundry?, classification?, width?, clear? }`.
    ///   - force: when true, overwrite already-populated values instead of only filling gaps.
    static func apply(_ updates: [Value], force: Bool, fontService: FontService) -> CallTool.Result {
        var results: [UpdateResult] = []

        for update in updates {
            guard let obj = update.objectValue else {
                results.append(UpdateResult(family: "", applied: [], skipped: [], error: "Each update must be an object.", effective: nil))
                continue
            }
            guard let family = obj["family"]?.stringValue, !family.trimmingCharacters(in: .whitespaces).isEmpty else {
                results.append(UpdateResult(family: "", applied: [], skipped: [], error: "Missing required 'family'.", effective: nil))
                continue
            }
            guard let font = fontService.fonts.first(where: { $0.familyName == family }) else {
                results.append(UpdateResult(family: family, applied: [], skipped: [], error: "No font family named '\(family)'.", effective: nil))
                continue
            }

            var applied: [String] = []
            var skipped: [Skip] = []

            // Clears run first so a same-call clear+set behaves predictably.
            for raw in (obj["clear"]?.arrayValue?.compactMap(\.stringValue) ?? []) {
                switch raw.lowercased() {
                case "foundry": fontService.resetFoundryOverride(for: font); applied.append("cleared foundry")
                case "classification": fontService.resetClassificationOverride(for: font); applied.append("cleared classification")
                case "width": fontService.resetWidthOverride(for: font); applied.append("cleared width")
                default: skipped.append(Skip(field: "clear", reason: "unknown attribute '\(raw)'"))
                }
            }

            // Foundry — gap = currently Unknown (no metadata, no override).
            if let foundry = obj["foundry"]?.stringValue {
                if fontService.effectiveFoundry(font) != nil && !force {
                    skipped.append(Skip(field: "foundry", reason: "already '\(fontService.displayFoundry(font))' — pass force:true to overwrite"))
                } else {
                    fontService.setFoundryOverride(foundry, for: font)
                    applied.append("foundry")
                }
            }

            // Classification — gap = currently Unclassified.
            if let raw = obj["classification"]?.stringValue {
                if let value = FontClassification(rawValue: raw) {
                    if fontService.effectiveClassification(font) != .unclassified && !force {
                        skipped.append(Skip(field: "classification", reason: "already '\(fontService.effectiveClassification(font).rawValue)' — pass force:true to overwrite"))
                    } else {
                        fontService.setClassificationOverride(value, for: font)
                        applied.append("classification")
                    }
                } else {
                    skipped.append(Skip(field: "classification", reason: "invalid value '\(raw)' (expected one of: \(FontClassification.allCases.map(\.rawValue).joined(separator: ", ")))"))
                }
            }

            // Width — gap = no width override yet (there's always a detected value).
            if let raw = obj["width"]?.stringValue {
                if let value = FontWidth(rawValue: raw) {
                    if fontService.isWidthOverridden(font) && !force {
                        skipped.append(Skip(field: "width", reason: "already set to '\(fontService.effectiveWidth(font).rawValue)' — pass force:true to overwrite"))
                    } else {
                        fontService.setWidthOverride(value, for: font)
                        applied.append("width")
                    }
                } else {
                    skipped.append(Skip(field: "width", reason: "invalid value '\(raw)' (expected one of: \(FontWidth.allCases.map(\.rawValue).joined(separator: ", ")))"))
                }
            }

            let effective = Effective(
                foundry: fontService.effectiveFoundry(font),
                classification: fontService.effectiveClassification(font).rawValue,
                width: fontService.effectiveWidth(font).rawValue
            )
            results.append(UpdateResult(family: family, applied: applied, skipped: skipped, error: nil, effective: effective))
        }

        let payload = Payload(results: results)
        let appliedCount = results.reduce(0) { $0 + $1.applied.count }
        let errorCount = results.filter { $0.error != nil }.count
        var summary = "Applied \(appliedCount) change(s) across \(results.count) family(ies)."
        if errorCount > 0 { summary += " \(errorCount) had errors." }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let structured = try? Value(payload)
        return CallTool.Result(content: [.text("\(summary)\n\n\(json)")], structuredContent: structured)
    }
}
