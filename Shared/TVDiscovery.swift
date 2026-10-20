import Foundation

/// A Samsung TV that answered on the local network.
struct DiscoveredTV: Identifiable, Equatable {
    let host: String
    let name: String
    let model: String
    let mac: String?
    var id: String { host }
}

/// Finds Samsung TVs by asking every address on the phone's Wi-Fi subnet for the TV description on port 8001.
/// Plain HTTP needs no multicast entitlement (SSDP and mDNS do), and the answer already carries name, model and MAC.
enum TVDiscovery {
    /// The phone's IPv4 address on Wi-Fi and its /24 prefix, like ("192.168.1.23", "192.168.1.").
    static func wifiAddress() -> (ip: String, prefix: String)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidate: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(bitPattern: ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: buffer)
            let name = String(cString: ifa.ifa_name)
            if name == "en0" { candidate = ip; break }          // Wi-Fi on iPhone
            if candidate == nil, name.hasPrefix("en") { candidate = ip }
        }
        guard let ip = candidate else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return (ip, parts[0...2].joined(separator: ".") + ".")
    }

    /// Scans the /24 subnet, addresses nearest the phone's own first, calling `found` for each TV as it answers.
    static func scan(timeout: TimeInterval = 3, found: @escaping (DiscoveredTV) -> Void) async -> [DiscoveredTV] {
        guard let (ip, prefix) = wifiAddress(), let own = Int(ip.split(separator: ".").last ?? "") else { return [] }
        let hosts = (1...254).filter { $0 != own }.sorted { abs($0 - own) < abs($1 - own) }.map { prefix + String($0) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var results: [DiscoveredTV] = []
        await withTaskGroup(of: DiscoveredTV?.self) { group in
            var pending = hosts[...]
            for _ in 0..<min(128, pending.count) {
                let host = pending.removeFirst()
                group.addTask { await probe(host, session) }
            }
            for await result in group {
                if let tv = result { results.append(tv); found(tv) }
                if let host = pending.popFirst() { group.addTask { await probe(host, session) } }
            }
        }
        return results
    }

    private static func probe(_ host: String, _ session: URLSession) async -> DiscoveredTV? {
        guard let url = URL(string: "http://\(host):8001/api/v2/"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(SamsungTV.Info.self, from: data) else { return nil }
        return DiscoveredTV(host: host, name: info.device.displayName, model: info.device.modelName, mac: info.device.wifiMac)
    }
}
