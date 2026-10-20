import Foundation

@MainActor
final class SetupModel: ObservableObject {
    enum Phase: Equatable {
        case searching
        case results
        case pairing(name: String)
        case success(name: String, percent: Int?)
        case failed(String)
    }

    /// The monitor's Allow prompt times out after about this long.
    static let pairTimeout = 60

    @Published var phase: Phase = .searching
    @Published var monitors: [DiscoveredMonitor] = []
    @Published var manualHost = ""
    @Published var remaining = 0

    private let client: IPControlClient
    /// Called with the backlight read right after pairing, if that read succeeded.
    private let onPaired: (Int?) -> Void
    private var searchTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?

    init(client: IPControlClient, onPaired: @escaping (Int?) -> Void) {
        self.client = client
        self.onPaired = onPaired
    }

    var trimmedManualHost: String {
        manualHost.trimmingCharacters(in: .whitespaces)
    }

    func isCurrent(_ monitor: DiscoveredMonitor) -> Bool {
        guard let config = client.config else { return false }
        if let serial = monitor.serial, let pairedSerial = config.serial { return serial == pairedSerial }
        return monitor.host == config.host
    }

    /// Called whenever the setup window is shown.
    func start() {
        if case .pairing = phase { return }
        search()
    }

    func search() {
        phase = .searching
        searchTask?.cancel()
        searchTask = Task {
            let found = await MonitorDiscovery.search()
            guard !Task.isCancelled else { return }
            monitors = found
            if phase == .searching { phase = .results }
        }
    }

    func connect(_ monitor: DiscoveredMonitor) {
        pair(host: monitor.host, monitor: monitor)
    }

    func connectManually() {
        let host = trimmedManualHost
        guard !host.isEmpty else { return }
        pair(host: host, monitor: nil)
    }

    func cancelPairing() {
        pairTask?.cancel()
    }

    private func pair(host: String, monitor: DiscoveredMonitor?) {
        pairTask?.cancel()
        phase = .pairing(name: monitor?.name ?? host)
        remaining = Self.pairTimeout
        pairTask = Task {
            let countdown = Task {
                while remaining > 0 {
                    try await Task.sleep(for: .seconds(1))
                    remaining -= 1
                }
            }
            defer { countdown.cancel() }
            do {
                var info = monitor
                if info == nil { info = await MonitorDiscovery.describe(host: host) }
                try await client.pair(host: host, serial: info?.serial, name: info?.name)
                let native = try? await client.getBacklight()
                phase = .success(name: info?.name ?? host, percent: native.map { Int(BrightnessModel.toPercent($0)) })
                onPaired(native)
            } catch {
                phase = Task.isCancelled ? .results : .failed(Self.message(for: error, host: host))
            }
        }
    }

    private static func message(for error: Error, host: String) -> String {
        switch error as? IPControlError {
        case .unauthorized?:
            return "The monitor declined the request, or the prompt timed out. Try again and select Allow on the monitor."
        case .unreachable?:
            return "Couldn't reach a monitor at \(host). Check that it's on, on the same network as this Mac, and that IP Remote is turned on."
        default:
            return error.localizedDescription
        }
    }
}
