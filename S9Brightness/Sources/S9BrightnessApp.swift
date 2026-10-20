import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BrightnessModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model.needsPairing {
            SetupWindow.show(model.setup)
        }
    }
}

@main
struct S9BrightnessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("S9 Brightness", systemImage: "sun.max") {
            MenuView(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: BrightnessModel
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
                    Image(systemName: "sun.min")
                    Slider(value: Binding(get: { model.percent }, set: { model.set($0) }), in: 0...100, step: 2)
                    Image(systemName: "sun.max")
                }

                HStack {
                    ForEach([25, 50, 75, 100], id: \.self) { preset in
                        Button("\(preset)%") { model.set(Double(preset)) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if !model.needsPairing {
                    Button("Change Monitor…") { SetupWindow.show(model.setup) }
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
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
