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
            case .background: model.disconnect()
            default: break
            }
        }
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var host = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "tv").font(.system(size: 64, weight: .light))
            Text("Tele").font(.largeTitle.weight(.semibold))
            Text("Enter your Samsung TV's IP address. The TV will ask you to allow Tele once.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            TextField("192.168.1.50", text: $host)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.title3.monospacedDigit())
                .padding(.horizontal, 48)
            Button {
                Task { await model.setup(host: host) }
            } label: {
                Group {
                    if model.state == .connecting || model.state == .pairing { ProgressView().tint(.black) } else { Text("Connect") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            .padding(.horizontal, 48)
            .disabled(host.isEmpty || model.state == .connecting || model.state == .pairing)
            if case .failed(let message) = model.state { Text(message).foregroundStyle(.red).font(.footnote) }
            if model.state == .pairing { Text("Look at the TV and choose Allow.").font(.footnote).foregroundStyle(.secondary) }
            Spacer()
        }
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
