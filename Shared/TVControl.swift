import Foundation

/// One-shot operations for intents: open the remote channel, act, close. The app keeps its own live session.
enum TVControl {
    static func connected(timeout: TimeInterval = 8) async throws -> SamsungTV {
        var config = TVStore.load()
        guard config.isConfigured else { throw TVError.notConfigured }
        let tv = SamsungTV(host: config.host, token: config.token)
        let token = try await tv.connect(timeout: timeout)
        if token != config.token { config.token = token; TVStore.save(config) }
        return tv
    }

    static func press(_ key: String) async throws {
        let tv = try await connected()
        defer { tv.disconnect() }
        try await tv.press(key)
        try? await Task.sleep(nanoseconds: 200_000_000)     // let the frame leave before closing
    }

    static func launch(_ app: TVApp) async throws {
        if case .key(let key) = app.target { try await press(key.rawValue); return }
        let config = TVStore.load()
        guard config.isConfigured else { throw TVError.notConfigured }
        let tv = SamsungTV(host: config.host, token: config.token)
        defer { tv.disconnect() }
        try await tv.launch(appId: app.appId, native: app.isTizenId)
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// KEY_POWER when the TV answers, Wake-on-LAN when it does not.
    static func togglePower() async throws {
        let config = TVStore.load()
        guard config.isConfigured else { throw TVError.notConfigured }
        let tv = SamsungTV(host: config.host, token: config.token)
        if let info = try? await tv.info(timeout: 2), info.isOn {
            try await press("KEY_POWER")
        } else {
            SamsungTV.wake(mac: config.mac, host: config.host)
        }
    }

    static func isOn() async -> Bool? {
        let config = TVStore.load()
        guard config.isConfigured else { return nil }
        return (try? await SamsungTV(host: config.host, token: config.token).info(timeout: 2))?.isOn
    }
}
