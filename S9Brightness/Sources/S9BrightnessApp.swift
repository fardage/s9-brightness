import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BrightnessModel()
    let updates = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model.needsPairing {
            SetupWindow.show(model.setup)
        }
    }
}

@main
enum AppEntry {
    static func main() {
        // Unit tests run inside the app. Skip the real app there: it would open the setup
        // window and read the keychain, which prompts for a differently signed Debug build.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApplication.shared.run()
        } else {
            S9BrightnessApp.main()
        }
    }
}

struct S9BrightnessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("S9 Brightness", systemImage: "sun.max") {
            MenuView(model: appDelegate.model, updates: appDelegate.updates)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: BrightnessModel
    @ObservedObject var updates: UpdateChecker
    @State private var launchAtLogin = Self.isLoginItemEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.monitorName ?? "Samsung monitor").font(.headline).lineLimit(1)
                Spacer()
                if !model.needsPairing {
                    Text("\(Int(model.percent))%").monospacedDigit().foregroundStyle(.secondary)
                }
            }

            if model.needsPairing {
                Text("Connect your monitor to control its brightness.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set Up…") { SetupWindow.show(model.setup) }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Button { model.step(by: -1) } label: {
                        Label("Decrease Brightness", systemImage: "sun.min").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.percent <= 0)
                    .help("Decrease by 2 %")
                    Slider(value: Binding(get: { model.percent }, set: { model.set($0) }), in: 0...100, step: 2)
                    Button { model.step(by: 1) } label: {
                        Label("Increase Brightness", systemImage: "sun.max").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.percent >= 100)
                    .help("Increase by 2 %")
                }

                HStack {
                    ForEach(Array(model.presets.values.enumerated()), id: \.offset) { index, preset in
                        Button("\(preset)%") { model.set(Double(preset)) }
                            .frame(maxWidth: .infinity)
                            .help("Right-click to change this preset")
                            .contextMenu {
                                Button("Set to Current Brightness (\(Int(model.percent))%)") { model.setPreset(index) }
                                Button("Reset Presets") { model.resetPresets() }
                            }
                    }
                }
            }

            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Menu {
                    Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    if !model.needsPairing {
                        Button("Change Monitor…") { SetupWindow.show(model.setup) }
                    }
                    if let release = updates.available {
                        Divider()
                        Button("Download Version \(release.version)…") { NSWorkspace.shared.open(release.url) }
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .overlay(alignment: .topTrailing) {
                    if updates.available != nil {
                        Circle().fill(.red).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
                }
                .help(updates.available.map { "Settings – version \($0.version) is available" } ?? "Settings")

                Spacer()

                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Quit S9 Brightness")
            }
        }
        .padding(14)
        .frame(width: 290)
        .onAppear {
            launchAtLogin = Self.isLoginItemEnabled
            model.refresh()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = Self.isLoginItemEnabled
    }

    private static var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
