import Foundation
import Observation
import XPlaneKit

/// Single source of truth for the UI: connection status, loaded subpanels and the live
/// position of every control. Owns the `XPlaneClient` and its update streams.
@MainActor
@Observable
final class PanelModel {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Desconectado"
            case .connecting: return "Conectando…"
            case .connected: return "Conectado"
            case .error(let message): return message
            }
        }
    }

    var host: String {
        didSet { UserDefaults.standard.set(host, forKey: Keys.host) }
    }
    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Keys.port) }
    }
    var showVerificationBadges: Bool {
        didSet { UserDefaults.standard.set(showVerificationBadges, forKey: Keys.badges) }
    }

    private(set) var status: Status = .disconnected
    private(set) var subpanels: [SubpanelDefinition] = []
    /// Control id → current position index (0 = bottom).
    private(set) var positions: [String: Int] = [:]
    /// Latest raw value for each lamp binding.
    private(set) var lampValues: [DatarefKey: XPValue] = [:]
    /// Datarefs the simulator did not recognise on the last connect.
    private(set) var unresolved: Set<String> = []
    private(set) var lastError: String?

    @ObservationIgnored private var client: XPlaneClient?
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []

    private enum Keys {
        static let host = "xp.host"
        static let port = "xp.port"
        static let badges = "ui.verificationBadges"
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: Keys.host) ?? "192.168.1.100"
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort == 0 ? 8087 : storedPort   // 8087 = xp_relay.py default
        showVerificationBadges = defaults.object(forKey: Keys.badges) as? Bool ?? true
        loadMappings()
    }

    // MARK: Mappings

    private func loadMappings() {
        guard let directory = Bundle.main.url(forResource: "mapping", withExtension: nil) else {
            lastError = "No se encontró la carpeta 'mapping' en el bundle."
            return
        }
        do {
            subpanels = try PanelLoader.loadAll(in: directory)
        } catch {
            lastError = "Error leyendo mapping: \(error.localizedDescription)"
        }
    }

    private var subscribedDatarefNames: [String] {
        var names = Set<String>()
        for control in subpanels.flatMap(\.controls) {
            if let state = control.state { names.insert(state.dataref) }
            if let top = control.lamps?.top?.dataref { names.insert(top) }
            if let bottom = control.lamps?.bottom?.dataref { names.insert(bottom) }
        }
        return Array(names)
    }

    // MARK: Connection

    func connect() {
        Task { await self.performConnect() }
    }

    func disconnect() {
        Task { await self.performDisconnect() }
    }

    func toggleConnection() {
        switch status {
        case .connected, .connecting: disconnect()
        case .disconnected, .error: connect()
        }
    }

    private func performConnect() async {
        await performDisconnect()
        status = .connecting
        lastError = nil

        let client = XPlaneClient(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
        self.client = client
        listen(to: client)

        do {
            try await client.connect()
            let missing = try await client.subscribe(datarefs: subscribedDatarefNames)
            unresolved = Set(missing)
            status = .connected
        } catch {
            status = .error(describe(error))
        }
    }

    private func performDisconnect() async {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        if let client {
            await client.disconnect()
        }
        client = nil
        status = .disconnected
    }

    private func listen(to client: XPlaneClient) {
        listeners.append(Task { [weak self] in
            for await update in client.updates {
                self?.apply(update)
            }
        })
        listeners.append(Task { [weak self] in
            for await state in client.stateChanges {
                self?.apply(state)
            }
        })
    }

    private func apply(_ state: XPlaneClient.State) {
        switch state {
        case .failed(let message):
            status = .error(message)
        case .disconnected:
            if status == .connected { status = .disconnected }
        case .connecting, .connected:
            break   // performConnect drives these transitions after subscribing.
        }
    }

    private func apply(_ update: DatarefUpdate) {
        for control in subpanels.flatMap(\.controls) {
            if let state = control.state, state.dataref == update.name,
               let element = update.value.element(at: state.index),
               let position = state.position(for: element, count: control.positions.count) {
                positions[control.id] = position
            }
            for lamp in [control.lamps?.top, control.lamps?.bottom].compactMap({ $0 })
            where lamp.dataref == update.name {
                if let key = lamp.key, let element = update.value.element(at: key.index) {
                    lampValues[key] = element
                }
            }
        }
    }

    // MARK: Interaction

    func position(of control: ControlDefinition) -> Int {
        positions[control.id] ?? 0
    }

    func isAvailable(_ control: ControlDefinition) -> Bool {
        guard status == .connected, let state = control.state else { return false }
        return !unresolved.contains(state.dataref)
    }

    /// Moves a lever switch one or more positions (positive = up).
    func move(_ control: ControlDefinition, by delta: Int) {
        guard let client else { return }
        let count = control.positions.count
        let current = position(of: control)
        let target = min(max(current + delta, 0), count - 1)
        guard target != current else { return }

        positions[control.id] = target   // optimistic; the subscription confirms or corrects
        Task {
            do {
                if let command = delta > 0 ? control.commands?.up : control.commands?.down {
                    for _ in 0..<abs(target - current) {
                        try await client.fire(command: command)
                    }
                } else if let binding = control.writeBinding {
                    try await client.write(binding.key, XPValue(binding.value(for: target, count: count)))
                }
            } catch {
                self.positions[control.id] = current
                self.lastError = self.describe(error)
            }
        }
    }

    /// Pushbutton press: fires `press` or cycles the bound value.
    func press(_ control: ControlDefinition) {
        guard let client else { return }
        let count = max(control.positions.count, 2)
        let current = position(of: control)
        let next = (current + 1) % count
        Task {
            do {
                if let command = control.commands?.press {
                    try await client.fire(command: command)
                } else if let binding = control.writeBinding {
                    try await client.write(binding.key, XPValue(binding.value(for: next, count: count)))
                }
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    func isLit(_ lamp: Lamp?) -> Bool {
        guard let lamp, let key = lamp.key else { return false }
        return lamp.isLit(lampValues[key])
    }

    private func describe(_ error: Error) -> String {
        if let xp = error as? XPlaneError, let text = xp.errorDescription { return text }
        return error.localizedDescription
    }
}
