import Foundation

enum TVError: LocalizedError {
    case notConfigured, timeout, denied, unreachable, badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set up the TV first."
        case .timeout: return "The TV did not answer in time."
        case .denied: return "The TV denied the connection. Allow Tele on the TV screen and try again."
        case .unreachable: return "The TV is not reachable on the network."
        case .badResponse(let code): return "The TV answered with status \(code)."
        }
    }
}

/// Samsung TV protocol client: REST (8001) for info and app launch, WebSocket (8002) for remote keys,
/// DIAL (8080) for title deep links, and Wake-on-LAN for power on.
final class SamsungTV: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    static let clientName = "Tele"

    let host: String
    private(set) var token: String
    private var channel: URLSessionWebSocketTask?
    private var listener: Task<Void, Never>?
    /// Text in the TV's focused field while its on-screen keyboard is up (the TV mirrors it over the channel).
    @MainActor private(set) var imeText: String?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(host: String, token: String = "") {
        self.host = host
        self.token = token
    }

    // MARK: TLS: the TV presents a self-signed certificate on 8002

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == host,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: REST

    struct Info: Decodable {
        struct Device: Decodable {
            let name: String
            let modelName: String
            let wifiMac: String?
            let PowerState: String?

            /// The TV escapes its name as HTML ("55&quot; Crystal UHD").
            var displayName: String {
                [("&quot;", "\""), ("&amp;", "&"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")]
                    .reduce(name) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            }
        }
        let device: Device
        var isOn: Bool { device.PowerState == "on" }
    }

    func info(timeout: TimeInterval = 3) async throws -> Info {
        var request = URLRequest(url: URL(string: "http://\(host):8001/api/v2/")!)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw TVError.unreachable }
        return try JSONDecoder().decode(Info.self, from: data)
    }

    /// Launches an app by its Samsung store ID or Tizen ID through the REST API.
    func launchREST(appId: String) async throws {
        var request = URLRequest(url: URL(string: "http://\(host):8001/api/v2/applications/\(appId)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Whether the TV lists an app with this id (store id or Tizen id).
    func isInstalled(appId: String) async -> Bool {
        var request = URLRequest(url: URL(string: "http://\(host):8001/api/v2/applications/\(appId)")!)
        request.timeoutInterval = 3
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Runs a tile: an app launch, or a key press for the TV's own Home screen.
    func open(_ app: TVApp) async throws {
        switch app.target {
        case .key(let key): try await press(key.rawValue)
        case .app(let id, let native): try await launch(appId: id, native: native)
        }
    }

    // MARK: DIAL deep links (Netflix "m=<id>", YouTube "v=<id>", ...)

    func dial(app: String, payload: String) async throws {
        var request = URLRequest(url: URL(string: "http://\(host):8080/ws/app/\(app)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.data(using: .utf8)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: WebSocket remote

    private var socketURL: URL {
        let name = Data(Self.clientName.utf8).base64EncodedString()
        var s = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if !token.isEmpty { s += "&token=\(token)" }
        return URL(string: s)!
    }

    /// Opens the remote channel. The first time, the TV shows an "Allow Tele?" prompt; the answer carries a token.
    @discardableResult
    func connect(timeout: TimeInterval) async throws -> String {
        if channel != nil { return token }
        let task = session.webSocketTask(with: socketURL)
        channel = task
        task.resume()
        do {
            let newToken = try await withTimeout(timeout) { try await self.awaitConnect(task) }
            if !newToken.isEmpty { token = newToken }
            listen(on: task)
            return token
        } catch {
            disconnect()
            throw error
        }
    }

    private func awaitConnect(_ task: URLSessionWebSocketTask) async throws -> String {
        while true {
            let message = try await task.receive()
            guard case .string(let text) = message,
                  let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let event = json["event"] as? String else { continue }
            switch event {
            case "ms.channel.connect":
                return (json["data"] as? [String: Any])?["token"] as? String ?? ""
            case "ms.channel.unauthorized":
                throw TVError.denied
            case "ms.channel.timeOut":
                throw TVError.timeout
            default:
                continue
            }
        }
    }

    func disconnect() {
        listener?.cancel()
        listener = nil
        channel?.cancel(with: .normalClosure, reason: nil)
        channel = nil
    }

    /// Follows the TV's keyboard: ms.remote.imeStart / imeUpdate (base64 text) / imeEnd.
    private func listen(on task: URLSessionWebSocketTask) {
        listener = Task { [weak self] in
            while !Task.isCancelled, let message = try? await task.receive() {
                guard case .string(let text) = message,
                      let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let event = json["event"] as? String else { continue }
                let update: String?? = switch event {
                case "ms.remote.imeStart": .some("")
                case "ms.remote.imeUpdate":
                    .some((json["data"] as? String).flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? "")
                case "ms.remote.imeEnd": .some(nil)
                default: nil
                }
                if let update { await MainActor.run { self?.imeText = update } }
            }
        }
    }

    /// Replaces the text in the TV's focused field.
    func sendText(_ text: String) async throws {
        try await sendJSON([
            "method": "ms.remote.control",
            "params": ["Cmd": Data(text.utf8).base64EncodedString(), "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"]
        ])
        await MainActor.run { imeText = text }
    }

    /// Removes the last character in the TV's text field; with no field open, sends the clear key.
    func backspace() async throws {
        if let text = await imeText, !text.isEmpty {
            try await sendText(String(text.dropLast()))
        } else {
            try await press(RemoteKey.clear.rawValue)
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task = channel else { throw TVError.unreachable }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func press(_ key: String) async throws {
        try await sendJSON([
            "method": "ms.remote.control",
            "params": ["Cmd": "Click", "DataOfCmd": key, "Option": "false", "TypeOfRemote": "SendRemoteKey"]
        ])
    }

    /// Launches an app over the remote channel. Store IDs use DEEP_LINK, Tizen IDs use NATIVE_LAUNCH.
    /// Opens an app. The REST endpoint needs no channel and is what this firmware honours; the channel's
    /// ed.apps.launch message is the fallback.
    func launch(appId: String, native: Bool, metaTag: String = "") async throws {
        if (try? await launchREST(appId: appId)) != nil { return }
        if channel == nil { try await connect(timeout: 8) }
        try await sendJSON([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch", "to": "host",
                "data": ["appId": appId, "action_type": native ? "NATIVE_LAUNCH" : "DEEP_LINK", "metaTag": metaTag]
            ]
        ])
    }

    // MARK: Wake-on-LAN

    /// Sends the magic packet three ways: plain unicast to the TV's own address (which iOS allows without the
    /// multicast entitlement, and which works while the TV keeps its Wi-Fi link up in standby), the subnet
    /// broadcast and the limited broadcast (both need com.apple.developer.networking.multicast on iOS 16+).
    /// Returns the errno per target; 0 means the kernel took the packet.
    @discardableResult
    static func wake(mac: String, host: String) -> [String: Int32] {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return [:] }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }
        var targets = [host]
        if let prefix = TVDiscovery.wifiAddress()?.prefix { targets.append(prefix + "255") }
        targets.append("255.255.255.255")
        var result: [String: Int32] = [:]
        for target in targets {
            let sock = socket(AF_INET, SOCK_DGRAM, 0)
            guard sock >= 0 else { result[target] = errno; continue }
            var yes: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
            var worst: Int32 = 0
            for port: in_port_t in [9, 7] {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr.s_addr = inet_addr(target)
                let sent = packet.withUnsafeBytes { raw in
                    withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(sock, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent < 0 { worst = errno }
            }
            result[target] = worst
            close(sock)
        }
        #if DEBUG
        print("wake", mac, result.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        #endif
        return result
    }

    /// Wakes the TV and waits until its REST service answers and reports power on. Repeats the magic packet
    /// every few seconds meanwhile; false when the TV stays silent until the timeout.
    static func wakeAndWait(mac: String, host: String, timeout: TimeInterval = 30) async -> Bool {
        let probe = SamsungTV(host: host)
        let deadline = Date().addingTimeInterval(timeout)
        var round = 0
        while Date() < deadline, !Task.isCancelled {
            if round % 3 == 0 { wake(mac: mac, host: host) }
            round += 1
            if let info = try? await probe.info(timeout: 2), info.isOn { return true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }
}

func withTimeout<T>(_ seconds: TimeInterval, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TVError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
