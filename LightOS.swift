// Menu bar app for Govee lights over the LAN API (same protocol as ../govee.py).
import AppKit
import Darwin
import ServiceManagement
import SwiftUI

struct Light: Identifiable {
    let ip: String
    let sku: String
    var on = false
    var id: String { ip }
    var name: String { sku + " · ." + (ip.split(separator: ".").last.map(String.init) ?? ip) }
}

enum Govee {
    static func addr(_ ip: String, _ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &a.sin_addr)
        return a
    }

    static func send(_ cmd: String, _ data: [String: Any], to ip: String, port: UInt16 = 4003) {
        guard let msg = try? JSONSerialization.data(withJSONObject: ["msg": ["cmd": cmd, "data": data]]) else { return }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var a = addr(ip, port)
        _ = msg.withUnsafeBytes { buf in
            withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Binds the reply port, runs `trigger`, then collects replies for `seconds`.
    static func listen(for seconds: Double, trigger: () -> Void) -> [(ip: String, data: [String: Any])] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var a = addr("0.0.0.0", 4002)
        let bound = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return [] }
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        trigger()
        var out: [(ip: String, data: [String: Any])] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0,
                  let json = try? JSONSerialization.jsonObject(with: Data(buf[0..<n])) as? [String: Any],
                  let msg = json["msg"] as? [String: Any],
                  let data = msg["data"] as? [String: Any] else { continue }
            out.append((String(cString: inet_ntoa(from.sin_addr)), data))  // H6076 omits ip, so use sender
        }
        return out
    }

    static func scan() -> [Light] {
        let replies = listen(for: 2) {
            for _ in 0..<2 {  // lights drop scans now and then; ask twice
                for target in ["239.255.255.250", "255.255.255.255"] {
                    send("scan", ["account_topic": "reserve"], to: target, port: 4001)
                }
                usleep(500_000)
            }
        }
        var found = [String: Light]()
        for r in replies {
            if let sku = r.data["sku"] as? String { found[r.ip] = Light(ip: r.ip, sku: sku) }
        }
        let status = listen(for: 1.5) { for ip in found.keys { send("devStatus", [:], to: ip) } }
        for s in status { if let on = s.data["onOff"] as? Int { found[s.ip]?.on = on == 1 } }
        return found.values.sorted { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
    }
}

@MainActor final class Store: ObservableObject {
    @Published var lights: [Light] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var brightness = 100.0
    @Published var kelvin = 4000.0
    @Published var color = Color.white
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var targets: [String] { selected.isEmpty ? lights.map(\.ip) : Array(selected) }

    init() {
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {  // on by default; user can turn it off
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
            setLaunchAtLogin(true)
        }
        refresh()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LightOS: launch at login: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        Task.detached {
            let found = Govee.scan()
            await MainActor.run {
                self.lights = found
                self.selected.formIntersection(found.map(\.ip))
                self.scanning = false
            }
        }
    }

    func power(_ on: Bool, ips: [String]? = nil) {
        let ips = ips ?? targets
        for ip in ips { Govee.send("turn", ["value": on ? 1 : 0], to: ip) }
        for i in lights.indices where ips.contains(lights[i].ip) { lights[i].on = on }
    }

    func applyBrightness() {
        for ip in targets { Govee.send("brightness", ["value": Int(brightness)], to: ip) }
    }

    func applyKelvin() {
        for ip in targets {
            Govee.send("colorwc", ["color": ["r": 0, "g": 0, "b": 0], "colorTemInKelvin": Int(kelvin)], to: ip)
        }
    }

    func apply(color c: Color) {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return }
        let rgb = ["r": Int(n.redComponent * 255), "g": Int(n.greenComponent * 255), "b": Int(n.blueComponent * 255)]
        for ip in targets { Govee.send("colorwc", ["color": rgb, "colorTemInKelvin": 0], to: ip) }
    }
}

struct Panel: View {
    @ObservedObject var store: Store
    let swatches: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    func showAbout() {
        let credits = NSMutableAttributedString()
        for (text, url) in [("github.com/bythebug", "https://github.com/bythebug"),
                            ("github.com/bythebug/lightos", "https://github.com/bythebug/lightos")] {
            if credits.length > 0 { credits.append(NSAttributedString(string: "\n")) }
            credits.append(NSAttributedString(string: text, attributes: [.link: URL(string: url)!, .font: NSFont.systemFont(ofSize: 11)]))
        }
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LightOS").font(.headline)
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Rescan")
            }

            if store.lights.isEmpty && !store.scanning {
                Text("No lights found. Check that LAN Control is on in the Govee app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.lights) { light in
                HStack {
                    Image(systemName: store.selected.contains(light.ip) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.selected.contains(light.ip) ? Color.accentColor : .secondary)
                    Text(light.name)
                    Spacer()
                    Toggle("", isOn: Binding(get: { light.on }, set: { store.power($0, ips: [light.ip]) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                .contentShape(Rectangle())
                .onTapGesture { store.selected.formSymmetricDifference([light.ip]) }
            }

            Divider()
            HStack {
                Text(store.selected.isEmpty ? "All lights" : "\(store.selected.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("On") { store.power(true) }
                Button("Off") { store.power(false) }
            }
            HStack {
                Image(systemName: "sun.min")
                Slider(value: $store.brightness, in: 1...100) { editing in if !editing { store.applyBrightness() } }
                Image(systemName: "sun.max")
            }
            HStack {
                Text("Warm").font(.caption)
                Slider(value: $store.kelvin, in: 2000...9000) { editing in if !editing { store.applyKelvin() } }
                Text("Cool").font(.caption)
            }
            HStack(spacing: 6) {
                ForEach(swatches, id: \.self) { c in
                    Circle().fill(c).frame(width: 20, height: 20)
                        .onTapGesture { store.apply(color: c) }
                }
                Spacer()
                ColorPicker("", selection: $store.color, supportsOpacity: false).labelsHidden()
            }
            .onChange(of: store.color) { _, c in store.apply(color: c) }

            Divider()
            HStack {
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("About") { showAbout() }.buttonStyle(.borderless)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            HStack(spacing: 4) {
                Text("LightOS \(version) · by").foregroundStyle(.secondary)
                Link("bythebug", destination: URL(string: "https://github.com/bythebug")!)
                Text("·").foregroundStyle(.secondary)
                Link("GitHub", destination: URL(string: "https://github.com/bythebug/lightos")!)
            }
            .font(.caption)
        }
        .padding()
        .frame(width: 290)
    }
}

@main struct LightOSApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra("LightOS", systemImage: "lightbulb.fill") { Panel(store: store) }
            .menuBarExtraStyle(.window)
    }
}
