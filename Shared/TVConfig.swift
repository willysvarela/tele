import Foundation

/// What the app and the widget share about the TV. Lives in the App Group so widget intents can act without the app.
struct TVConfig: Codable, Equatable {
    var host = ""
    var name = ""
    var model = ""
    var mac = ""
    var token = ""

    var isConfigured: Bool { !host.isEmpty }
    var isPaired: Bool { !token.isEmpty }
}

enum TVStore {
    static let suite = "group.com.willys.tele"
    private static let key = "tv.config"

    static var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    static func load() -> TVConfig {
        if let data = defaults.data(forKey: key),
           let config = try? JSONDecoder().decode(TVConfig.self, from: data) { return config }
        #if DEBUG
        // Simulator convenience: `xcrun simctl launch --setenv`-style, via SIMCTL_CHILD_TELE_HOST=<ip>.
        if let host = ProcessInfo.processInfo.environment["TELE_HOST"], !host.isEmpty {
            return TVConfig(host: host, name: "Samsung TV")
        }
        #endif
        return TVConfig()
    }

    /// What the setup screen pre-fills: `TeleDefaultHost` from Info.plist (TELE_DEFAULT_HOST in Local.xcconfig),
    /// otherwise the phone's own subnet so only the last number is left to type.
    static var suggestedHost: String {
        if let host = Bundle.main.object(forInfoDictionaryKey: "TeleDefaultHost") as? String, !host.isEmpty { return host }
        return TVDiscovery.wifiAddress()?.prefix ?? ""
    }

    static func save(_ config: TVConfig) {
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: key) }
    }
}
