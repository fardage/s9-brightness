import Foundation

@MainActor
final class BrightnessModel: ObservableObject {
    @Published var percent: Double = 0
    @Published var status = ""
    @Published var needsPairing = false
    @Published var monitorName: String?
    @Published private(set) var presets = Presets.load()

    private let client = IPControlClient()
    lazy var setup = SetupModel(client: client) { [weak self] native in self?.paired(native) }

    private var pendingNative: Int?
    private var writing = false
    private var rediscovering = false
    private var lastSent = Date.distantPast
    // The IP Control service needs ~0.3 s between requests.
    private let minInterval: TimeInterval = 0.3

    init() {
        needsPairing = !client.isPaired
        monitorName = client.config?.name
    }

    static func toPercent(_ native: Int) -> Double {
        (Double(native) * 100 / Double(IPControlClient.nativeMax)).rounded()
    }

    static func toNative(_ percent: Double) -> Int {
        Int((percent * Double(IPControlClient.nativeMax) / 100).rounded())
    }

    /// Reads the current backlight, e.g. when the menu opens, so changes made on the monitor show up.
    func refresh() {
        guard !writing, !rediscovering else { return }
        readBacklight()
    }

    /// Slider and preset writes; coalesced so only the latest value is sent.
    func set(_ value: Double) {
        percent = value
        pendingNative = Self.toNative(value)
        guard !writing else { return }
        writing = true
        Task { await drain() }
    }

    /// Stores the current brightness in a preset slot.
    func setPreset(_ index: Int) {
        presets.update(index, to: Int(percent))
        presets.save()
    }

    func resetPresets() {
        presets = Presets()
        presets.save()
    }

    private func readBacklight() {
        guard client.isPaired else {
            needsPairing = true
            return
        }
        Task {
            do {
                let native = try await client.getBacklight()
                if !writing { percent = Self.toPercent(native) }
                setOK()
            } catch {
                handle(error)
            }
        }
    }

    private func drain() async {
        defer { writing = false }
        while pendingNative != nil {
            let wait = minInterval - Date().timeIntervalSince(lastSent)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let target = pendingNative else { break }
            pendingNative = nil
            do {
                let native = try await client.setBacklight(target)
                lastSent = Date()
                if pendingNative == nil { percent = Self.toPercent(native) }
                setOK()
            } catch {
                lastSent = Date()
                handle(error)
                pendingNative = nil
            }
        }
    }

    private func paired(_ native: Int?) {
        setOK()
        monitorName = client.config?.name
        if let native {
            percent = Self.toPercent(native)
        } else {
            refresh()
        }
    }

    private func setOK() {
        status = ""
        needsPairing = false
    }

    private func handle(_ error: Error) {
        status = error.localizedDescription
        switch error as? IPControlError {
        case .notPaired?, .unauthorized?, .certificateChanged?:
            needsPairing = true
        case .unreachable?:
            rediscover(after: error)
        default:
            break
        }
    }

    /// The monitor may have a new IP (DHCP); look for it by serial number and follow it.
    private func rediscover(after error: Error) {
        guard !rediscovering, let serial = client.config?.serial else { return }
        rediscovering = true
        status = "Looking for the monitor on the network…"
        Task {
            defer { rediscovering = false }
            let match = await MonitorDiscovery.search().first { $0.serial == serial }
            guard let match else {
                status = error.localizedDescription
                return
            }
            guard match.ipControl else {
                status = "IP Remote is turned off on the monitor (\(MonitorDiscovery.ipRemoteMenuPath))."
                return
            }
            guard match.host != client.config?.host else {
                status = error.localizedDescription
                return
            }
            do {
                try client.updateHost(match.host)
            } catch {
                status = error.localizedDescription
                return
            }
            readBacklight()
        }
    }
}
