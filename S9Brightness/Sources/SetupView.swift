import AppKit
import SwiftUI

/// Hosts the setup flow in a regular window; menu bar apps have no main window to put it in.
@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show(_ setup: SetupModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: SetupView(setup: setup) { resize(to: $0) })
            // Automatic sizing feeds window resizes back into SwiftUI layout and can make
            // AppKit throw ("needs another Update Constraints pass"). Instead the view
            // reports its ideal size and the window follows.
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Set Up S9 Brightness"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        setup.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func resize(to size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        // Keep the title bar in place while the height changes.
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    static func close() {
        window?.close()
    }
}

struct SetupView: View {
    @ObservedObject var setup: SetupModel
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your Samsung monitor").font(.title2.bold())
                Text("S9 Brightness sets the monitor's backlight over your local network.")
                    .foregroundStyle(.secondary)
            }
            if showsRequirements {
                requirements
            }
            content
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Resize after the current layout pass rather than during it.
            DispatchQueue.main.async { onSizeChange(size) }
        }
    }

    /// The requirements matter while finding or choosing a monitor, not once pairing has started.
    private var showsRequirements: Bool {
        switch setup.phase {
        case .searching, .results, .failed: return true
        case .pairing, .success: return false
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before you start").font(.subheadline.weight(.semibold))
            Label("Connect the monitor to Wi-Fi, on the same network as this Mac.", systemImage: "wifi")
            Label("Turn on IP Remote on the monitor: \(MonitorDiscovery.ipRemoteMenuPath) › IP Remote.",
                  systemImage: "switch.2")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }

    @ViewBuilder
    private var content: some View {
        switch setup.phase {
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching your network…")
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        case .results:
            results
        case .pairing(let name):
            pairing(name)
        case .success(let name, let percent):
            success(name, percent)
        case .failed(let message):
            failed(message)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            if setup.monitors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No Samsung monitors found", systemImage: "magnifyingglass").font(.headline)
                    Text("""
                        • Make sure the monitor is on and on the same network as this Mac.
                        • Allow S9 Brightness in System Settings › Privacy & Security › Local Network.
                        • Otherwise enter the IP address shown in the monitor's network settings below.
                        """)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(setup.monitors) { monitor in
                    MonitorRow(monitor: monitor, isCurrent: setup.isCurrent(monitor)) { setup.connect(monitor) }
                }
            }

            DisclosureGroup("Enter IP address manually") {
                HStack {
                    TextField("IP address", text: $setup.manualHost)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { setup.connectManually() }
                    Button("Connect") { setup.connectManually() }
                        .disabled(setup.trimmedManualHost.isEmpty)
                }
                .padding(.top, 4)
            }

            HStack(alignment: .top) {
                Text("Samsung allows one connected app per monitor; connecting replaces any other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Search Again") { setup.search() }
            }
        }
    }

    private func pairing(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Check your monitor", systemImage: "hand.tap").font(.headline)
            Text("Select Allow on the prompt shown on \(name). The monitor must be showing your Mac's screen, not the Samsung Home screen.")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(setup.remaining), total: Double(SetupModel.pairTimeout))
            HStack {
                Text("Waiting for approval… \(setup.remaining) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { setup.cancelPairing() }
            }
        }
    }

    private func success(_ name: String, _ percent: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connected to \(name)", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text((percent.map { "Current brightness is \($0)%. " } ?? "") + "Use the sun icon in the menu bar to change it.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { SetupWindow.close() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't connect", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Back") { setup.phase = .results }
                Button("Search Again") { setup.search() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct MonitorRow: View {
    let monitor: DiscoveredMonitor
    let isCurrent: Bool
    let connect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.name).font(.headline)
                Text([monitor.model, monitor.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !monitor.ipControl {
                    Label("IP Remote is off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    Text("On the monitor, open \(MonitorDiscovery.ipRemoteMenuPath) and turn on IP Remote, then click Search Again.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isCurrent {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if monitor.ipControl {
                Button(isCurrent ? "Reconnect" : "Connect", action: connect)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}
