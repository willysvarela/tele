import SwiftUI

// MARK: - Remote screen

/// The remote as a fixed instrument: nothing scrolls vertically, the navigation disc and the two rockers sit
/// within the thumb's reach at the bottom, and keys fire on touch-down like physical ones.
struct RemoteView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 6)
            AppGrid().padding(.top, 22)
            Spacer(minLength: 16)
            transport
            navigation.padding(.top, 18)
            cluster.padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await model.connect() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.config.name.isEmpty ? "Samsung TV" : model.config.name)
                    .font(.title2.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                }
                if case .failed(let message) = model.state {
                    Text(message).font(.footnote).foregroundStyle(Palette.live).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            RoundKey("power", size: 46, tint: model.isOn == false ? Palette.standby : Palette.live,
                     label: model.isOn == false ? "Turn the TV on" : "Turn the TV off", fire: .up) { model.power() }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 46, height: 46)
                    .background(KeyFace(pressed: false, shape: Circle()))
            }
            .buttonStyle(TileStyle())
            .accessibilityLabel("Settings")
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .ready: return model.isOn == false ? .orange : Palette.standby
        case .connecting, .pairing: return .yellow
        case .failed: return Palette.live
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

    private var transport: some View {
        HStack(spacing: 16) {
            RoundKey("backward.fill", label: "Rewind") { model.press(.rewind) }
            RoundKey("play.fill", label: "Play") { model.press(.play) }
            RoundKey("pause.fill", label: "Pause") { model.press(.pause) }
            RoundKey("forward.fill", label: "Fast forward") { model.press(.fastForward) }
        }
    }

    private var navigation: some View {
        HStack(spacing: 16) {
            RoundKey("arrow.uturn.backward", label: "Back") { model.press(.back) }
            RoundKey("house.fill", label: "Home") { model.press(.home) }
            RoundKey("rectangle.inset.filled.and.person.filled", label: "Source") { model.press(.source) }
        }
    }

    private var cluster: some View {
        HStack(spacing: 0) {
            Rocker(top: KeyAction("plus", "Volume up") { model.press(.volumeUp) },
                   middle: KeyAction("speaker.slash.fill", "Mute") { model.press(.mute) },
                   bottom: KeyAction("minus", "Volume down") { model.press(.volumeDown) },
                   repeats: true)
            Spacer(minLength: 8)
            NavigationDisc()
            Spacer(minLength: 8)
            Rocker(top: KeyAction("chevron.up", "Channel up") { model.press(.channelUp) },
                   middle: KeyAction("list.bullet.rectangle.fill", "Guide") { model.press(.guide) },
                   bottom: KeyAction("chevron.down", "Channel down") { model.press(.channelDown) })
        }
    }
}

// MARK: - Palette

enum Palette {
    static let canvas = Color.black
    static let key = Color(red: 0.118, green: 0.118, blue: 0.125)          // graphite
    static let keyPressed = Color(red: 0.21, green: 0.21, blue: 0.22)
    static let disc = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let ink = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let live = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let standby = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let rim = LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
}

// MARK: - Keys

struct KeyAction {
    let symbol: String
    let label: String
    let action: () -> Void
    init(_ symbol: String, _ label: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.action = action
    }
}

enum KeyFire { case down, up }

/// A key that fires when the finger lands, like a physical one, optionally repeating while held.
/// `fire: .up` makes it act on release instead, for keys where a slip would be costly.
struct Key<Content: View>: View {
    var fire: KeyFire = .down
    var repeats = false
    let label: String
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content

    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        content(pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        if fire == .down {
                            action()
                            if repeats { startRepeating() }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeater?.cancel()
                        repeater = nil
                        if fire == .up { action() }
                    }
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func startRepeating() {
        repeater = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }
}

/// Rubber key face: graphite with a light top rim, a shade lighter while pressed.
struct KeyFace<S: InsettableShape>: View {
    let pressed: Bool
    let shape: S

    var body: some View {
        shape.fill(pressed ? Palette.keyPressed : Palette.key)
            .overlay(shape.strokeBorder(Palette.rim, lineWidth: 1))
    }
}

struct RoundKey: View {
    let symbol: String
    var size: CGFloat = 56
    var tint: Color = Palette.ink
    let label: String
    var fire: KeyFire = .down
    let action: () -> Void

    init(_ symbol: String, size: CGFloat = 56, tint: Color = Palette.ink, label: String, fire: KeyFire = .down,
         action: @escaping () -> Void) {
        self.symbol = symbol; self.size = size; self.tint = tint; self.label = label; self.fire = fire; self.action = action
    }

    var body: some View {
        Key(fire: fire, label: label, action: action) { pressed in
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(KeyFace(pressed: pressed, shape: Circle()))
                .contentShape(Circle())
                .scaleEffect(pressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.1), value: pressed)
        }
    }
}

/// Press feedback for tiles and ordinary buttons (which fire on release so they can live inside a scroll view).
struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Navigation disc

enum Direction: CaseIterable {
    case up, right, down, left

    var angle: Double {                      // degrees, clockwise from 3 o'clock (screen coordinates)
        switch self { case .up: -90; case .right: 0; case .down: 90; case .left: 180 }
    }
    var symbol: String {
        switch self { case .up: "chevron.up"; case .right: "chevron.right"; case .down: "chevron.down"; case .left: "chevron.left" }
    }
    var label: String {
        switch self { case .up: "Up"; case .right: "Right"; case .down: "Down"; case .left: "Left" }
    }
    var key: RemoteKey {
        switch self { case .up: .up; case .right: .right; case .down: .down; case .left: .left }
    }
    func offset(_ distance: CGFloat) -> CGSize {
        switch self {
        case .up: CGSize(width: 0, height: -distance)
        case .right: CGSize(width: distance, height: 0)
        case .down: CGSize(width: 0, height: distance)
        case .left: CGSize(width: -distance, height: 0)
        }
    }
}

/// A quarter of the ring between the OK dome and the rim.
struct Wedge: Shape {
    let direction: Direction
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let from = Angle.degrees(direction.angle - 45), to = Angle.degrees(direction.angle + 45)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// One big disc: four arrow wedges around a white OK dome. Arrows repeat while held.
struct NavigationDisc: View {
    @EnvironmentObject private var model: RemoteModel
    private let diameter: CGFloat = 216
    private let dome: CGFloat = 90

    var body: some View {
        ZStack {
            Circle().fill(Palette.disc)
                .overlay(Circle().strokeBorder(Palette.rim, lineWidth: 1))
            ForEach(Direction.allCases, id: \.self) { direction in
                wedge(direction)
            }
            Key(label: "OK", action: { model.press(.ok) }) { pressed in
                Circle().fill(pressed ? Color(white: 0.84) : .white)
                    .overlay(Text("OK").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.black))
                    .frame(width: dome, height: dome)
                    .contentShape(Circle())
                    .scaleEffect(pressed ? 0.95 : 1)
                    .animation(.easeOut(duration: 0.1), value: pressed)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func wedge(_ direction: Direction) -> some View {
        let shape = Wedge(direction: direction, inner: dome / 2 + 3)
        return Key(repeats: true, label: direction.label, action: { model.press(direction.key) }) { pressed in
            shape.fill(pressed ? Color.white.opacity(0.09) : Color.clear)
                .overlay(
                    Image(systemName: direction.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .offset(direction.offset(diameter / 2 - 30))
                )
                .contentShape(shape)
        }
    }
}

// MARK: - Rocker

/// A tall rocker with a press-in middle, like the volume and channel keys on the TV's own remote.
struct Rocker: View {
    let top: KeyAction
    let middle: KeyAction
    let bottom: KeyAction
    var repeats = false

    private let width: CGFloat = 56
    private let height: CGFloat = 216
    private let middleHeight: CGFloat = 54

    var body: some View {
        ZStack {
            Capsule().fill(Palette.key)
            VStack(spacing: 0) {
                zone(top, size: 19, weight: .bold, height: (height - middleHeight) / 2, repeats: repeats)
                zone(middle, size: 13, weight: .semibold, height: middleHeight, dim: true)
                zone(bottom, size: 19, weight: .bold, height: (height - middleHeight) / 2, repeats: repeats)
            }
            VStack {
                Spacer(); hairline; Spacer().frame(height: middleHeight); hairline; Spacer()
            }
            .frame(height: height)
            Capsule().strokeBorder(Palette.rim, lineWidth: 1)
        }
        .frame(width: width, height: height)
        .clipShape(Capsule())
    }

    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 22, height: 1)
    }

    private func zone(_ key: KeyAction, size: CGFloat, weight: Font.Weight, height: CGFloat,
                      repeats: Bool = false, dim: Bool = false) -> some View {
        Key(repeats: repeats, label: key.label, action: key.action) { pressed in
            Rectangle().fill(pressed ? Color.white.opacity(0.09) : Color.clear)
                .overlay(
                    Image(systemName: key.symbol)
                        .font(.system(size: size, weight: weight))
                        .foregroundStyle(dim ? Color.secondary : Palette.ink)
                )
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - App grid

/// Every app in view at once, four to a row, so nothing on the remote scrolls.
struct AppGrid: View {
    @EnvironmentObject private var model: RemoteModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(TVApp.allCases, id: \.self) { app in
                Button { model.launch(app) } label: {
                    VStack(spacing: 7) {
                        AppMark(app: app).aspectRatio(1, contentMode: .fit)
                        Text(app.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel("Open \(app.title)")
            }
        }
        .padding(.horizontal, 24)
    }
}

/// Brand-coloured tile with a monogram; the same idea as the tiles on the TV launcher.
struct AppMark: View {
    let app: TVApp

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(background)
            .overlay(mark)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var background: AnyShapeStyle {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        func vertical(_ a: UInt32, _ b: UInt32) -> AnyShapeStyle {
            AnyShapeStyle(LinearGradient(colors: [rgb(a), rgb(b)], startPoint: .top, endPoint: .bottom))
        }
        switch app {
        case .launcher: return vertical(0xF5F5F7, 0xD6D6DC)
        case .netflix: return vertical(0xE50914, 0xA80710)
        case .youtube: return AnyShapeStyle(rgb(0xFF0000))
        case .primeVideo: return AnyShapeStyle(rgb(0x00A8E1))
        case .disneyPlus: return vertical(0x1A3BA6, 0x071A52)
        case .hboMax: return vertical(0x2A1F8F, 0x120C4D)
        case .spotify: return AnyShapeStyle(rgb(0x1DB954))
        case .globoplay: return AnyShapeStyle(LinearGradient(colors: [rgb(0xFF2D55), rgb(0xFF7A00)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    @ViewBuilder private var mark: some View {
        switch app {
        case .launcher: Image(systemName: "square.grid.2x2.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.black)
        case .netflix: Text("N").font(.system(size: 36, weight: .black)).foregroundStyle(.white)
        case .youtube: Image(systemName: "play.rectangle.fill").font(.system(size: 30)).foregroundStyle(.white)
        case .primeVideo: Text("prime").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        case .disneyPlus: Text("D+").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        case .hboMax: Text("HBO").font(.system(size: 17, weight: .black)).foregroundStyle(.white)
        case .spotify: Image(systemName: "music.note").font(.system(size: 26, weight: .bold)).foregroundStyle(.black)
        case .globoplay: Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(.white)
        }
    }
}
