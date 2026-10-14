import Foundation
import MCP

/// Host/Origin validator that permits the addresses this server is actually reachable at:
/// loopback, Tailscale CGNAT IPs (100.64.0.0/10), and MagicDNS names (`*.ts.net`).
///
/// The SDK's default `OriginValidator.localhost()` only allows loopback, so requests from
/// the Tailnet (e.g. the Pi hitting `100.x.y.z:8787`) are rejected with
/// "Misdirected Request: Host header not allowed". We still reject arbitrary external
/// hostnames, which keeps DNS-rebinding protection meaningful — the server only ever
/// binds to loopback + the Tailscale interface, and the Tailnet is the trust boundary.
struct TailnetOriginValidator: HTTPRequestValidator {
    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        if let host = request.header(HTTPHeaderName.host), !isAllowed(hostName(from: host)) {
            return .error(
                statusCode: 421,
                .invalidRequest("Misdirected Request: Host header not allowed"),
                sessionID: context.sessionID
            )
        }
        // Origin is only sent by browsers; non-browser MCP clients omit it. When present,
        // hold it to the same rule.
        if let origin = request.header(HTTPHeaderName.origin), !isAllowed(hostName(from: stripScheme(origin))) {
            return .error(
                statusCode: 403,
                .invalidRequest("Forbidden: Origin not allowed"),
                sessionID: context.sessionID
            )
        }
        return nil
    }

    // MARK: - Host classification

    private func isAllowed(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "::1" || h.hasPrefix("127.") { return true }
        if h.hasSuffix(".ts.net") { return true }
        return isTailscaleIPv4(h)
    }

    /// Strips a trailing `:port` (and IPv6 brackets) from a Host/authority string.
    private func hostName(from raw: String) -> String {
        var s = raw
        if s.hasPrefix("["), let end = s.firstIndex(of: "]") {
            return String(s[s.index(after: s.startIndex)..<end])
        }
        if let colon = s.lastIndex(of: ":"), s[s.index(after: colon)...].allSatisfy(\.isNumber) {
            s = String(s[..<colon])
        }
        return s
    }

    private func stripScheme(_ origin: String) -> String {
        guard let range = origin.range(of: "://") else { return origin }
        return String(origin[range.upperBound...])
    }

    /// True when `host` is an IPv4 literal inside Tailscale's CGNAT range 100.64.0.0/10.
    private func isTailscaleIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        var octets: [UInt32] = []
        for part in parts {
            guard let value = UInt32(part), value <= 255 else { return false }
            octets.append(value)
        }
        let ip = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        // 100.64.0.0/10 → top 10 bits are 0110010001
        return (ip >> 22) == 0b0110010001
    }
}
