import Foundation
import SwiftUI
import WidgetKit

/// Live session for the app: keeps the remote channel open while on screen, so key presses are instant.
@MainActor
final class RemoteModel: ObservableObject {
    enum State: Equatable { case idle, connecting, pairing, ready, failed(String) }

    @Published var config = TVStore.load()
    @Published var state: State = .idle
    @Published var isOn: Bool?
    @Published var busy = false

    private var tv: SamsungTV?

    // MARK: setup

    /// Looks the TV up, stores what it reports, then pairs (the TV asks the viewer to allow Tele).
    func setup(host: String) async {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        state = .connecting
        let probe = SamsungTV(host: host)
        do {
            let info = try await probe.info(timeout: 4)
            config = TVConfig(host: host, name: info.device.name, model: info.device.modelName,
                              mac: info.device.wifiMac ?? config.mac, token: "")
            TVStore.save(config)
            await connect()
        } catch {
            state = .failed("No Samsung TV answered at \(host).")
        }
    }

    func forget() {
        disconnect()
        config = TVConfig()
        TVStore.save(config)
        state = .idle
        isOn = nil
    }

    // MARK: session

    func connect() async {
        guard config.isConfigured else { return }
        if tv != nil, state == .ready { return }
        let session = SamsungTV(host: config.host, token: config.token)
        state = config.isPaired ? .connecting : .pairing
        do {
            let token = try await session.connect(timeout: config.isPaired ? 8 : 45)
            if token != config.token { config.token = token; TVStore.save(config) }
            tv = session
            state = .ready
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            tv = nil
            state = .failed((error as? TVError)?.errorDescription ?? error.localizedDescription)
        }
        await refreshStatus()
    }

    func disconnect() {
        tv?.disconnect()
        tv = nil
        if state == .ready { state = .idle }
    }

    func refreshStatus() async {
        guard config.isConfigured else { return }
        let info = try? await SamsungTV(host: config.host, token: config.token).info(timeout: 2)
        isOn = info?.isOn
        if let name = info?.device.name, name != config.name { config.name = name; TVStore.save(config) }
    }

    // MARK: actions

    func press(_ key: RemoteKey) {
        haptic()
        Task { await run { tv in try await tv.press(key.rawValue) } }
    }

    func launch(_ app: TVApp) {
        haptic()
        Task { await run { tv in try await tv.launch(appId: app.appId, native: app.isTizenId) } }
    }

    func power() {
        haptic()
        Task {
            if isOn == false {
                SamsungTV.wake(mac: config.mac, host: config.host)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await refreshStatus()
            } else {
                await run { tv in try await tv.press(RemoteKey.power.rawValue) }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refreshStatus()
            }
        }
    }

    private func run(_ action: (SamsungTV) async throws -> Void) async {
        if tv == nil || state != .ready { await connect() }
        guard let tv else { return }
        do {
            try await action(tv)
        } catch {
            self.tv = nil
            state = .failed((error as? TVError)?.errorDescription ?? error.localizedDescription)
            await connect()                              // one reconnect, then retry once
            if let tv = self.tv { try? await action(tv) }
        }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
