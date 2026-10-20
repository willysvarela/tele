import AppIntents
import SwiftUI
import WidgetKit

@main
struct TeleWidgetBundle: WidgetBundle {
    var body: some Widget {
        TeleWidget()
        TelePowerControl()
        TeleMuteControl()
        TeleLauncherControl()
    }
}

// MARK: - Home Screen widget

struct TeleEntry: TimelineEntry {
    let date: Date
    let name: String
    let isOn: Bool?
}

struct TeleProvider: TimelineProvider {
    func placeholder(in context: Context) -> TeleEntry { TeleEntry(date: .now, name: "Samsung TV", isOn: true) }

    func getSnapshot(in context: Context, completion: @escaping (TeleEntry) -> Void) {
        completion(TeleEntry(date: .now, name: TVStore.load().name, isOn: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TeleEntry>) -> Void) {
        Task {
            let on = await TVControl.isOn()
            let entry = TeleEntry(date: .now, name: TVStore.load().name, isOn: on)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct TeleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TeleWidget", provider: TeleProvider()) { entry in
            TeleWidgetView(entry: entry)
        }
        .configurationDisplayName("TV remote")
        .description("Power, volume and your apps, one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TeleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TeleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(entry.isOn == true ? .green : entry.isOn == false ? .orange : .gray).frame(width: 7, height: 7)
                Text(entry.name.isEmpty ? "Samsung TV" : entry.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            if family == .systemSmall {
                HStack(spacing: 8) {
                    key("power", intent: TogglePowerIntent(), tint: .red)
                    key("speaker.slash.fill", intent: PressKeyIntent(key: .mute))
                }
                HStack(spacing: 8) {
                    key("minus", intent: PressKeyIntent(key: .volumeDown))
                    key("plus", intent: PressKeyIntent(key: .volumeUp))
                }
            } else {
                HStack(spacing: 8) {
                    key("power", intent: TogglePowerIntent(), tint: .red)
                    key("speaker.slash.fill", intent: PressKeyIntent(key: .mute))
                    key("minus", intent: PressKeyIntent(key: .volumeDown))
                    key("plus", intent: PressKeyIntent(key: .volumeUp))
                    key("playpause.fill", intent: PressKeyIntent(key: .play))
                }
                HStack(spacing: 8) {
                    app("square.grid.2x2.fill", "Launcher", .launcher)
                    app("n.square.fill", "Netflix", .netflix)
                    app("play.rectangle.fill", "YouTube", .youtube)
                }
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.055, green: 0.059, blue: 0.07) }
    }

    private func key(_ symbol: String, intent: some AppIntent, tint: Color = .white) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
    }

    private func app(_ symbol: String, _ title: String, _ app: TVApp) -> some View {
        Button(intent: LaunchAppIntent(app: app)) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Control Center / Lock Screen controls (iOS 18)

struct TelePowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TelePowerControl") {
            ControlWidgetButton(action: TogglePowerIntent()) {
                Label("TV power", systemImage: "power")
            }
        }
        .displayName("TV power")
        .description("Turns the TV off, or wakes it.")
    }
}

struct TeleMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TeleMuteControl") {
            ControlWidgetButton(action: PressKeyIntent(key: .mute)) {
                Label("Mute TV", systemImage: "speaker.slash")
            }
        }
        .displayName("Mute TV")
        .description("Mutes or unmutes the TV.")
    }
}

struct TeleLauncherControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TeleLauncherControl") {
            ControlWidgetButton(action: LaunchAppIntent(app: .launcher)) {
                Label("Launcher", systemImage: "square.grid.2x2")
            }
        }
        .displayName("Open launcher")
        .description("Opens the launcher on the TV.")
    }
}
