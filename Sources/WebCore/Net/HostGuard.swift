import Foundation

/// Which addresses the crawl may reach: public hosts over http(s), never this Mac, its network or a name that
/// resolves to either.
///
/// PIN: CHECKED BY NAME AND BY ADDRESS. A literal (`127.0.0.1`, `[::1]`, `10.0.0.2`) and a local name
/// (`localhost`, `printer.local`, a single label) are refused as written; any other name is resolved and refused
/// when an address it gives is private, so a public name pointed at a private address goes nowhere either. Every
/// redirect is checked again.
public enum HostGuard {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    /// The URL as written: scheme, and a host that is not local by its name or its literal address.
    public static func check(_ url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .refused("only http and https are read")
        }
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return .refused("no host") }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal")
            || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") {
            return .refused("a local host")
        }
        if let octets = ipv4(host) { return isPublic(v4: octets) ? .allowed : .refused("a private address") }
        if host.contains(":") { return isPublic(v6: host) ? .allowed : .refused("a private address") }
        if !host.contains(".") { return .refused("a local host") }
        return .allowed
    }

    /// The URL as written, then every address its host resolves to.
    public static func checkResolving(_ url: URL) async -> Verdict {
        let written = check(url)
        guard written == .allowed, let host = url.host(percentEncoded: false), ipv4(host) == nil, !host.contains(":") else { return written }
        let addresses = await resolve(host)
        if addresses.isEmpty { return .refused("the host does not resolve") }
        for address in addresses {
            if let octets = ipv4(address), !isPublic(v4: octets) { return .refused("the host resolves to a private address") }
            if address.contains(":"), !isPublic(v6: address) { return .refused("the host resolves to a private address") }
        }
        return .allowed
    }

    static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    static func isPublic(v4 o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _): return false
        case (169, 254): return false
        case (172, 16...31): return false
        case (192, 168): return false
        case (100, 64...127): return false   // carrier-grade NAT
        case (192, 0) where o[2] == 0: return false
        case (198, 18...19): return false
        case (224...255, _): return false    // multicast and reserved
        default: return true
        }
    }

    static func isPublic(v6 address: String) -> Bool {
        let a = address.lowercased()
        if a == "::" || a == "::1" { return false }
        if a.hasPrefix("fe8") || a.hasPrefix("fe9") || a.hasPrefix("fea") || a.hasPrefix("feb") { return false } // link-local
        if a.hasPrefix("fc") || a.hasPrefix("fd") { return false }   // unique local
        if a.hasPrefix("ff") { return false }                         // multicast
        if a.hasPrefix("::ffff:"), let octets = ipv4(String(a.dropFirst(7))) { return isPublic(v4: octets) }
        return true
    }

    /// The host's addresses, as the system resolver gives them, off the caller's thread.
    static func resolve(_ host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                                     ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                    continuation.resume(returning: [])
                    return
                }
                defer { freeaddrinfo(first) }
                var addresses: [String] = []
                var cursor: UnsafeMutablePointer<addrinfo>? = first
                while let info = cursor {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let address = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        addresses.append(address.split(separator: "%").first.map(String.init) ?? address)
                    }
                    cursor = info.pointee.ai_next
                }
                continuation.resume(returning: addresses)
            }
        }
    }
}
