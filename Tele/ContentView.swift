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

/// Finds TVs on the Wi-Fi and pairs with the chosen one. Shown full screen for the first TV and as a sheet
/// ("Add a TV") for the next ones.
struct SetupView: View {
    var embedded = false

    @EnvironmentObject private var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var host = TVStore.suggestedHost
    @State private var found: [DiscoveredTV] = []
    @State private var scanning = false
    @State private var scanned = false

    private var busy: Bool { model.state == .connecting || model.state == .pairing }

    var body: some View {
        if embedded {
            NavigationStack {
                content
                    .navigationTitle("Add a TV")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                if embedded {
                    Text("Pick the TV to add. It will ask you to allow Tele once.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .padding(.horizontal, 32).padding(.top, 24)
                } else {
                    Image(systemName: "tv").font(.system(size: 56, weight: .light)).padding(.top, 56)
                    Text("Tele").font(.largeTitle.weight(.semibold))
                    Text("Pick your Samsung TV. It will ask you to allow Tele once.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
                }

                VStack(spacing: 10) {
                    ForEach(found) { tv in
                        Button {
                            host = tv.host
                            Task { await add(tv.host) }
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
                    .onSubmit { Task { await add(host) } }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit())
                    .padding(.horizontal, 48)
                Button {
                    Task { await add(host) }
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

    private func add(_ host: String) async {
        await model.setup(host: host)
        if embedded, case .failed = model.state { return }
        if embedded { dismiss() }
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

// MARK: - Devices

/// Every TV the app knows: tap one to use it, swipe for default and remove, add another.
struct DevicesView: View {
    @EnvironmentObject private var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.devices) { device in
                        Button {
                            model.use(device)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv").font(.title3).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name.isEmpty ? device.host : device.name).font(.headline)
                                    Text("\(device.model)   \(device.host)").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if device.id == model.defaultID {
                                    Text("Default").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(.white.opacity(0.1), in: Capsule())
                                }
                                if device.id == model.config.id {
                                    Image(systemName: "checkmark").font(.body.weight(.semibold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { model.remove(device) } label: { Label("Remove", systemImage: "trash") }
                            if device.id != model.defaultID {
                                Button { model.makeDefault(device) } label: { Label("Default", systemImage: "star") }.tint(.blue)
                            }
                        }
                        .contextMenu {
                            if device.id != model.defaultID { Button("Make default") { model.makeDefault(device) } }
                            Button("Remove", role: .destructive) { model.remove(device) }
                        }
                    }
                } footer: {
                    Text("Tele opens on the default TV. The widget, Control Center and Shortcuts use it too.")
                }
                Section {
                    Button { adding = true } label: { Label("Add a TV", systemImage: "plus") }
                }
            }
            .navigationTitle("Devices")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) { SetupView(embedded: true) }
        }
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
                    LabeledContent("Tele launcher", value: model.hasLauncher ? "Installed" : "Not found")
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
