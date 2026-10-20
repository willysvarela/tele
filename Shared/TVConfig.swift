import Foundation

/// One TV. The list of TVs and the default live in the App Group so widget intents can act without the app.
struct TVConfig: Codable, Equatable, Identifiable {
    var host = ""
    var name = ""
    var model = ""
    var mac = ""
    var token = ""

    var id: String { mac.isEmpty ? host : mac }
    var isConfigured: Bool { !host.isEmpty }
    var isPaired: Bool { !token.isEmpty }
}

enum TVStore {
    static let suite = "group.com.willys.tele"
    private static let devicesKey = "tv.devices"
    private static let defaultKey = "tv.default"
    private static let legacyKey = "tv.config"

    static var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    /// Every TV the app knows, in the order they were added.
    static func devices() -> [TVConfig] {
        if let data = defaults.data(forKey: devicesKey),
           let list = try? JSONDecoder().decode([TVConfig].self, from: data) { return list }
        // One-time move from the single-TV layout.
        if let data = defaults.data(forKey: legacyKey),
           let one = try? JSONDecoder().decode(TVConfig.self, from: data), one.isConfigured {
            saveAll([one])
            setDefault(one.id)
            defaults.removeObject(forKey: legacyKey)
            return [one]
        }
        #if DEBUG
        // Simulator conveniences: SIMCTL_CHILD_TELE_HOST=<ip> stands in for a stored TV, and
        // SIMCTL_CHILD_TELE_DEMO=1 shows sample TVs with no network at all (store screenshots).
        if ProcessInfo.processInfo.environment["TELE_DEMO"] != nil {
            return [TVConfig(host: "192.168.1.20", name: "Living room", model: "QN65S90D", mac: "00:00:00:00:00:01"),
                    TVConfig(host: "192.168.1.21", name: "Bedroom", model: "UN43DU7700", mac: "00:00:00:00:00:02")]
        }
        if let host = ProcessInfo.processInfo.environment["TELE_HOST"], !host.isEmpty {
            return [TVConfig(host: host, name: "Samsung TV")]
        }
        #endif
        return []
    }

    static func defaultID() -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TELE_DEMO"] != nil { return "00:00:00:00:00:01" }
        #endif
        return defaults.string(forKey: defaultKey)
    }

    /// What the setup screen pre-fills: `TeleDefaultHost` from Info.plist (TELE_DEFAULT_HOST in Local.xcconfig),
    /// otherwise the phone's own subnet so only the last number is left to type.
    static var suggestedHost: String {
        if let host = Bundle.main.object(forInfoDictionaryKey: "TeleDefaultHost") as? String, !host.isEmpty { return host }
        return TVDiscovery.wifiAddress()?.prefix ?? ""
    }

    static func setDefault(_ id: String) { defaults.set(id, forKey: defaultKey) }

    /// The TV the app opens on and the widget, Control Center and Shortcuts act on: the default, else the first.
    static func load() -> TVConfig {
        let list = devices()
        if let id = defaultID(), let device = list.first(where: { $0.id == id }) { return device }
        return list.first ?? TVConfig()
    }

    /// Adds the TV or updates the stored one with the same identity. The first TV becomes the default.
    static func save(_ config: TVConfig) {
        var list = devices()
        if let index = list.firstIndex(where: { $0.id == config.id || $0.host == config.host }) {
            list[index] = config
        } else {
            list.append(config)
        }
        saveAll(list)
        if let id = defaultID(), list.contains(where: { $0.id == id }) { return }
        setDefault(config.id)
    }

    static func remove(id: String) {
        var list = devices()
        list.removeAll { $0.id == id }
        saveAll(list)
        if defaultID() == id {
            if let first = list.first { setDefault(first.id) } else { defaults.removeObject(forKey: defaultKey) }
        }
    }

    private static func saveAll(_ list: [TVConfig]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: devicesKey) }
    }
}
