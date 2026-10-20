import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RemoteModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.config.isConfigured { RemoteView() } else { SetupView() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.connect() }
            case .background: if model.state != .pairing { model.disconnect() }
            default: break
            }
        }
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var host = TVStore.suggestedHost
    @State private var found: [DiscoveredTV] = []
    @State private var scanning = false
    @State private var scanned = false

    private var busy: Bool { model.state == .connecting || model.state == .pairing }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "tv").font(.system(size: 56, weight: .light)).padding(.top, 56)
                Text("Tele").font(.largeTitle.weight(.semibold))
                Text("Pick your Samsung TV. It will ask you to allow Tele once.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)

                VStack(spacing: 10) {
                    ForEach(found) { tv in
                        Button {
                            host = tv.host
                            Task { await model.setup(host: tv.host) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tv").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).font(.headline)
                                    Text("\(tv.model)   \(tv.host)").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if busy && model.config.host == tv.host { ProgressView() }
                                else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            }
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    HStack(spacing: 8) {
                        if scanning { ProgressView().controlSize(.small) }
                        Text(scanning ? "Looking for TVs on your Wi-Fi…"
                             : found.isEmpty && scanned ? "No TV answered. Is it on and on this Wi-Fi?" : "")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        if !scanning { Button("Scan again") { Task { await scan() } }.font(.footnote) }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)

                Text("Or type the TV's IP address").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                TextField("192.168.1.50", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit { connect() }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit())
                    .padding(.horizontal, 48)
                Button {
                    connect()
                } label: {
                    Group {
                        if busy { ProgressView().tint(.black) } else { Text("Connect") }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                .padding(.horizontal, 48)
                .disabled(host.isEmpty || host.hasSuffix(".") || busy)
                if case .failed(let message) = model.state { Text(message).foregroundStyle(.red).font(.footnote) }
                if model.state == .pairing { Text("Look at the TV and choose Allow.").font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await scan() }
    }

    private func connect() {
        Task { await model.setup(host: host) }
    }

    private func scan() async {
        guard !scanning else { return }
        scanning = true
        found = []
        _ = await TVDiscovery.scan { tv in
            Task { @MainActor in
                if !found.contains(tv) { found.append(tv) }
                if host.isEmpty || host.hasSuffix(".") { host = tv.host }
            }
        }
        scanning = false
        scanned = true
    }
}

// MARK: - Remote

struct RemoteView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                HStack(spacing: 14) {
                    KeyButton("power", tint: model.isOn == false ? .green : .red) { model.power() }
                    KeyButton("house.fill") { model.press(.home) }
                    KeyButton("arrow.uturn.backward") { model.press(.back) }
                    KeyButton("rectangle.inset.filled.and.person.filled") { model.press(.source) }
                }
                dpad
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        KeyButton("plus") { model.press(.volumeUp) }
                        Text("VOL").font(.caption2).foregroundStyle(.secondary)
                        KeyButton("minus") { model.press(.volumeDown) }
                    }
                    Spacer()
                    KeyButton("speaker.slash.fill") { model.press(.mute) }
                    Spacer()
                    VStack(spacing: 10) {
                        KeyButton("chevron.up") { model.press(.channelUp) }
                        Text("CH").font(.caption2).foregroundStyle(.secondary)
                        KeyButton("chevron.down") { model.press(.channelDown) }
                    }
                }
                .padding(.horizontal, 24)
                HStack(spacing: 14) {
                    KeyButton("backward.fill") { model.press(.rewind) }
                    KeyButton("play.fill") { model.press(.play) }
                    KeyButton("pause.fill") { model.press(.pause) }
                    KeyButton("forward.fill") { model.press(.fastForward) }
                }
                apps
                if case .failed(let message) = model.state {
                    Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await model.connect() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.config.name.isEmpty ? "Samsung TV" : model.config.name).font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.title3) }
                .tint(.secondary)
        }
        .padding(.top, 8)
    }

    private var statusColor: Color {
        switch model.state {
        case .ready: return model.isOn == false ? .orange : .green
        case .connecting, .pairing: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch model.state {
        case .ready: return model.isOn == false ? "Standby" : "Connected"
        case .connecting: return "Connecting"
        case .pairing: return "Allow Tele on the TV"
        case .failed: return "Not connected"
        case .idle: return model.config.host
        }
    }

    private var dpad: some View {
        VStack(spacing: 8) {
            KeyButton("chevron.up", size: 64) { model.press(.up) }
            HStack(spacing: 8) {
                KeyButton("chevron.left", size: 64) { model.press(.left) }
                Button { model.press(.ok) } label: {
                    Text("OK").font(.title3.weight(.semibold))
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(.white)).foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                KeyButton("chevron.right", size: 64) { model.press(.right) }
            }
            KeyButton("chevron.down", size: 64) { model.press(.down) }
        }
        .padding(.vertical, 6)
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps").font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(TVApp.allCases, id: \.self) { app in
                    Button { model.launch(app) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: app.symbol).font(.title2)
                            Text(app.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).frame(height: 72)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Round key. Pressing gives a light haptic through the model.
struct KeyButton: View {
    let symbol: String
    var size: CGFloat = 56
    var tint: Color = .white
    let action: () -> Void

    init(_ symbol: String, size: CGFloat = 56, tint: Color = .white, action: @escaping () -> Void) {
        self.symbol = symbol; self.size = size; self.tint = tint; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(white: 0.16)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: RemoteModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("TV") {
                    LabeledContent("Name", value: model.config.name)
                    LabeledContent("Model", value: model.config.model)
                    LabeledContent("Address", value: model.config.host)
                    LabeledContent("MAC", value: model.config.mac)
                    LabeledContent("Paired", value: model.config.isPaired ? "Yes" : "No")
                }
                Section {
                    Button("Pair again") { model.config.token = ""; TVStore.save(model.config); Task { await model.connect() }; dismiss() }
                    Button("Forget this TV", role: .destructive) { model.forget(); dismiss() }
                } footer: {
                    Text("Wake needs \"Power On with Mobile\" enabled on the TV (Settings > General > Network > Expert Settings).")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
