import Foundation
import SwiftUI
import WidgetKit

/// Live session for the app: keeps the remote channel open while on screen, so key presses are instant.
@MainActor
final class RemoteModel: ObservableObject {
    enum State: Equatable { case idle, connecting, pairing, ready, failed(String) }

    @Published var config = TVStore.load()
    @Published var devices = TVStore.devices()
    @Published var defaultID = TVStore.defaultID()
    @Published var state: State = .idle
    @Published var isOn: Bool?
    @Published var busy = false
    /// Whether this TV has the Tele launcher installed; decides what the Home key opens.
    @Published var hasLauncher = false

    private var tv: SamsungTV?
    private var connecting: Task<Void, Never>?

    // MARK: setup

    /// Looks the TV up, stores what it reports, then pairs (the TV asks the viewer to allow Tele).
    func setup(host: String) async {
        let host = host.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.hasSuffix(".") else { return }
        state = .connecting
        let probe = SamsungTV(host: host)
        do {
            let info = try await probe.info(timeout: 4)
            let mac = info.device.wifiMac ?? ""
            let known = devices.first { (!mac.isEmpty && $0.mac == mac) || $0.host == host }
            disconnect()
            config = TVConfig(host: host, name: info.device.displayName, model: info.device.modelName,
                              mac: mac, token: known?.token ?? "")
            TVStore.save(config)
            reloadDevices()
            await connect()
        } catch {
            state = .failed("No Samsung TV answered at \(host).")
        }
    }

    // MARK: devices

    func use(_ device: TVConfig) {
        guard device.id != config.id else { return }
        disconnect()
        state = .idle
        isOn = nil
        hasLauncher = false
        config = device
        Task { await connect() }
    }

    func makeDefault(_ device: TVConfig) {
        TVStore.setDefault(device.id)
        reloadDevices()
    }

    func remove(_ device: TVConfig) {
        TVStore.remove(id: device.id)
        reloadDevices()
        guard device.id == config.id else { return }
        disconnect()
        state = .idle
        isOn = nil
        hasLauncher = false
        config = TVStore.load()
        if config.isConfigured { Task { await connect() } }
    }

    func forget() { remove(config) }

    private func reloadDevices() {
        devices = TVStore.devices()
        defaultID = TVStore.defaultID()
    }

    // MARK: session

    func connect() async {
        guard config.isConfigured else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TELE_DEMO"] != nil {        // store screenshots: look connected
            state = .ready; isOn = true; hasLauncher = true; return
        }
        #endif
        if tv != nil, state == .ready { return }
        if let inFlight = connecting { await inFlight.value; return }
        let task = Task { await openChannel() }
        connecting = task
        await task.value
        connecting = nil
    }

    private func openChannel() async {
        let session = SamsungTV(host: config.host, token: config.token)
        state = config.isPaired ? .connecting : .pairing
        // Pairing often means leaving the app to press Allow with another remote; keep running meanwhile.
        let keepAlive = state == .pairing ? UIApplication.shared.beginBackgroundTask(withName: "pairing") : .invalid
        defer { if keepAlive != .invalid { UIApplication.shared.endBackgroundTask(keepAlive) } }
        do {
            let token = try await session.connect(timeout: config.isPaired ? 8 : 60)
            if token != config.token { config.token = token; TVStore.save(config) }
            tv = session
            state = .ready
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            session.disconnect()
            tv = nil
            state = .failed((error as? TVError)?.errorDescription ?? error.localizedDescription)
        }
        await refreshStatus()
    }

    func disconnect() {
        connecting?.cancel()
        connecting = nil
        tv?.disconnect()
        tv = nil
        if state == .ready { state = .idle }
    }

    func refreshStatus() async {
        guard config.isConfigured else { return }
        let probe = SamsungTV(host: config.host, token: config.token)
        let info = try? await probe.info(timeout: 2)
        isOn = info?.isOn
        if info != nil { hasLauncher = await probe.isInstalled(appId: TVApp.launcher.appId) }
        if let name = info?.device.displayName, name != config.name { config.name = name; TVStore.save(config) }
    }

    // MARK: actions

    func press(_ key: RemoteKey) {
        haptic()
        Task { await run { tv in try await tv.press(key.rawValue) } }
    }

    func launch(_ app: TVApp) {
        haptic()
        Task { await run { tv in try await tv.open(app) } }
    }

    /// Home opens the Tele launcher when the TV has it, otherwise the TV's own Home screen.
    func home() {
        haptic()
        let launcher = hasLauncher
        Task {
            await run { tv in
                if launcher { try await tv.launch(appId: TVApp.launcher.appId, native: true) }
                else { try await tv.press(RemoteKey.home.rawValue) }
            }
        }
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
