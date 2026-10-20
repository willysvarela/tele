import AppIntents
import Foundation

/// Remote keys the TV understands over the remote channel.
enum RemoteKey: String, AppEnum {
    case power = "KEY_POWER", home = "KEY_HOME", back = "KEY_RETURN", exit = "KEY_EXIT"
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT", ok = "KEY_ENTER"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case channelUp = "KEY_CHUP", channelDown = "KEY_CHDOWN"
    case play = "KEY_PLAY", pause = "KEY_PAUSE", stop = "KEY_STOP", rewind = "KEY_REWIND", fastForward = "KEY_FF"
    case source = "KEY_SOURCE", menu = "KEY_MENU", guide = "KEY_GUIDE", info = "KEY_INFO"
    case zero = "KEY_0", one = "KEY_1", two = "KEY_2", three = "KEY_3", four = "KEY_4"
    case five = "KEY_5", six = "KEY_6", seven = "KEY_7", eight = "KEY_8", nine = "KEY_9", clear = "KEY_CLEAR"

    static let digits: [RemoteKey] = [.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV key")
    static var caseDisplayRepresentations: [RemoteKey: DisplayRepresentation] = [
        .power: "Power", .home: "Home", .back: "Back", .exit: "Exit",
        .up: "Up", .down: "Down", .left: "Left", .right: "Right", .ok: "OK",
        .volumeUp: "Volume up", .volumeDown: "Volume down", .mute: "Mute",
        .channelUp: "Channel up", .channelDown: "Channel down",
        .play: "Play", .pause: "Pause", .stop: "Stop", .rewind: "Rewind", .fastForward: "Fast forward",
        .zero: "0", .one: "1", .two: "2", .three: "3", .four: "4", .five: "5", .six: "6", .seven: "7",
        .eight: "8", .nine: "9", .clear: "Clear",
        .source: "Source", .menu: "Menu", .guide: "Guide", .info: "Info"
    ]
}

/// Apps worth one tap. Store IDs launch with DEEP_LINK; Tizen IDs (with a dot) with NATIVE_LAUNCH.
/// `tvHome` is the TV's own Home screen, reached with a key press rather than a launch.
enum TVApp: String, AppEnum, CaseIterable {
    case launcher, tvHome, netflix, youtube, primeVideo, disneyPlus, hboMax, appleTV, spotify, globoplay

    enum Target {
        case app(id: String, native: Bool)
        case key(RemoteKey)
    }

    /// Tiles on the remote screen. The launcher is not one of them (the Home key opens it) and Globoplay stays
    /// available to Shortcuts only.
    static let tiles: [TVApp] = [.tvHome, .netflix, .youtube, .primeVideo, .disneyPlus, .hboMax, .appleTV, .spotify]

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV app")
    static var caseDisplayRepresentations: [TVApp: DisplayRepresentation] = [
        .launcher: "Launcher", .tvHome: "TV Home", .netflix: "Netflix", .youtube: "YouTube",
        .primeVideo: "Prime Video", .disneyPlus: "Disney+", .hboMax: "HBO Max", .appleTV: "Apple TV",
        .spotify: "Spotify", .globoplay: "Globoplay"
    ]

    var target: Target {
        self == .tvHome ? .key(.home) : .app(id: appId, native: isTizenId)
    }

    var title: String {
        switch self {
        case .launcher: return "Launcher"
        case .tvHome: return "TV Home"
        case .netflix: return "Netflix"
        case .youtube: return "YouTube"
        case .primeVideo: return "Prime Video"
        case .disneyPlus: return "Disney+"
        case .hboMax: return "HBO Max"
        case .appleTV: return "Apple TV"
        case .spotify: return "Spotify"
        case .globoplay: return "Globoplay"
        }
    }

    var appId: String {
        switch self {
        case .launcher: return "MinLaunchr.Launcher"
        case .tvHome: return ""
        case .netflix: return "3201907018807"
        case .youtube: return "111299001912"
        case .primeVideo: return "3201910019365"
        case .disneyPlus: return "3201901017640"
        case .hboMax: return "3202301029760"
        case .appleTV: return "3201807016597"
        case .spotify: return "3201606009684"
        case .globoplay: return "LnLzvqrcEY.globo"
        }
    }

    var isTizenId: Bool { appId.contains(".") }

    var symbol: String {
        switch self {
        case .launcher: return "square.grid.2x2.fill"
        case .tvHome: return "tv.fill"
        case .netflix: return "n.square.fill"
        case .youtube: return "play.rectangle.fill"
        case .primeVideo: return "p.square.fill"
        case .disneyPlus: return "sparkles.tv.fill"
        case .hboMax: return "m.square.fill"
        case .appleTV: return "appletv.fill"
        case .spotify: return "music.note"
        case .globoplay: return "g.square.fill"
        }
    }
}

// MARK: - Intents (used by the widget, Control Center and Shortcuts)

struct PressKeyIntent: AppIntent {
    static var title: LocalizedStringResource = "Press TV key"
    static var description = IntentDescription("Sends a remote key to the TV.")

    @Parameter(title: "Key") var key: RemoteKey

    init() {}
    init(key: RemoteKey) { self.key = key }

    func perform() async throws -> some IntentResult {
        try await TVControl.press(key.rawValue)
        return .result()
    }
}

struct LaunchAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open app on TV"
    static var description = IntentDescription("Opens an app on the TV.")

    @Parameter(title: "App") var app: TVApp

    init() {}
    init(app: TVApp) { self.app = app }

    func perform() async throws -> some IntentResult {
        try await TVControl.launch(app)
        return .result()
    }
}

struct TogglePowerIntent: AppIntent {
    static var title: LocalizedStringResource = "TV power"
    static var description = IntentDescription("Turns the TV off, or wakes it when it is off.")

    func perform() async throws -> some IntentResult {
        try await TVControl.togglePower()
        return .result()
    }
}

struct TeleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TogglePowerIntent(),
                    phrases: ["Toggle the TV with \(.applicationName)", "Turn the TV on with \(.applicationName)"],
                    shortTitle: "TV power", systemImageName: "power")
        AppShortcut(intent: PressKeyIntent(key: .mute),
                    phrases: ["Mute the TV with \(.applicationName)"],
                    shortTitle: "Mute TV", systemImageName: "speaker.slash")
        AppShortcut(intent: LaunchAppIntent(app: .launcher),
                    phrases: ["Open the launcher with \(.applicationName)"],
                    shortTitle: "Open launcher", systemImageName: "square.grid.2x2")
    }
}
