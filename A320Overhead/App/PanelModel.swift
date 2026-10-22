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
        case reconnecting(attempt: Int)
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Desconectado"
            case .connecting: return "Conectando…"
            case .connected: return "Conectado"
            case .reconnecting(let attempt): return "Reconectando… (intento \(attempt))"
            case .error(let message): return message
            }
        }

        var isActive: Bool {
            switch self {
            case .connected, .connecting, .reconnecting: return true
            case .disconnected, .error: return false
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
    /// Datarefs added from the diagnostics screen, on top of the ones the mapping needs.
    private(set) var extraDatarefs: [String] {
        didSet { UserDefaults.standard.set(extraDatarefs, forKey: Keys.extras) }
    }

    private(set) var status: Status = .disconnected
    private(set) var subpanels: [SubpanelDefinition] = []
    /// Flight Control Unit mapping (`mapping/fcu/fcu.json`), nil when the file is missing.
    private(set) var fcu: FCUDefinition?
    /// Control id → current position index (0 = bottom).
    private(set) var positions: [String: Int] = [:]
    /// Latest raw value for each lamp binding.
    private(set) var lampValues: [DatarefKey: XPValue] = [:]
    /// Latest raw value of every subscribed dataref, keyed by name.
    private(set) var rawValues: [String: XPValue] = [:]
    /// When each dataref element last changed, keyed by "name" or "name[index]".
    private(set) var changeStamps: [String: Date] = [:]
    /// Datarefs the simulator did not recognise on the last connect.
    private(set) var unresolved: Set<String> = []
    private(set) var lastError: String?
    private(set) var lastCommandResult: String?

    @ObservationIgnored private var client: XPlaneClient?
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var reconnectAttempt = 0

    private enum Keys {
        static let host = "xp.host"
        static let port = "xp.port"
        static let badges = "ui.verificationBadges"
        static let extras = "diag.extraDatarefs"
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: Keys.host) ?? "192.168.1.100"
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort == 0 ? 8087 : storedPort   // 8087 = xp_relay.py default
        showVerificationBadges = defaults.object(forKey: Keys.badges) as? Bool ?? true
        extraDatarefs = defaults.stringArray(forKey: Keys.extras) ?? []
        loadMappings()
    }

    // MARK: Mappings

    private func loadMappings() {
        guard let directory = Bundle.main.url(forResource: "mapping", withExtension: nil) else {
            lastError = "No se encontró la carpeta 'mapping' en el bundle."
            return
        }
        let fileManager = FileManager.default
        let overheadDirectory = directory.appendingPathComponent("overhead", isDirectory: true)
        do {
            // Older bundles kept the overhead JSON at the root of `mapping/`.
            let source = fileManager.fileExists(atPath: overheadDirectory.path) ? overheadDirectory : directory
            subpanels = try PanelLoader.loadAll(in: source)
        } catch {
            lastError = "Error leyendo mapping/overhead: \(error.localizedDescription)"
        }
        let fcuDirectory = directory.appendingPathComponent("fcu", isDirectory: true)
        if fileManager.fileExists(atPath: fcuDirectory.path) {
            do {
                fcu = try FCULoader.loadFirst(in: fcuDirectory)
            } catch {
                lastError = "Error leyendo mapping/fcu: \(error.localizedDescription)"
            }
        }
    }

    var allControls: [ControlDefinition] {
        subpanels.flatMap(\.controls)
    }

    private var mappedDatarefNames: Set<String> {
        var names = Set<String>()
        for control in allControls {
            if let state = control.state { names.insert(state.dataref) }
            if let top = control.lamps?.top?.dataref { names.insert(top) }
            if let bottom = control.lamps?.bottom?.dataref { names.insert(bottom) }
        }
        if let fcu { names.formUnion(fcu.datarefNames) }
        return names
    }

    var subscribedDatarefNames: [String] {
        Array(mappedDatarefNames.union(extraDatarefs)).sorted()
    }

    // MARK: Connection

    func connect() {
        wantsConnection = true
        reconnectAttempt = 0
        Task { await self.performConnect() }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await self.performDisconnect() }
    }

    func toggleConnection() {
        if status.isActive {
            disconnect()
        } else {
            connect()
        }
    }

    private func performConnect() async {
        await performDisconnect()
        status = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        lastError = nil

        let client = XPlaneClient(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
        self.client = client
        listen(to: client)

        do {
            try await client.connect()
            let missing = try await client.subscribe(datarefs: subscribedDatarefNames)
            unresolved = Set(missing)
            reconnectAttempt = 0
            status = .connected
        } catch {
            status = .error(describe(error))
            scheduleReconnect()
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

    /// Exponential backoff (2, 4, 8, then 15 s) while the user still wants a connection.
    private func scheduleReconnect() {
        guard wantsConnection, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 15)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.wantsConnection else { return }
            self.reconnectTask = nil
            await self.performConnect()
        }
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
            scheduleReconnect()
        case .disconnected:
            if status == .connected { status = .disconnected }
        case .connecting, .connected:
            break   // performConnect drives these transitions after subscribing.
        }
    }

    private func apply(_ update: DatarefUpdate) {
        stampChanges(for: update)
        rawValues[update.name] = update.value

        for control in allControls {
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

    private func stampChanges(for update: DatarefUpdate) {
        let now = Date()
        let previous = rawValues[update.name]
        if let newArray = update.value.arrayValue {
            let oldArray = previous?.arrayValue ?? []
            for (index, value) in newArray.enumerated() where index >= oldArray.count || oldArray[index] != value {
                if previous != nil { changeStamps["\(update.name)[\(index)]"] = now }
            }
        } else if let previous, previous != update.value {
            changeStamps[update.name] = now
        }
    }

    // MARK: Interaction

    func position(of control: ControlDefinition) -> Int {
        positions[control.id] ?? 0
    }

    func isAvailable(_ control: ControlDefinition) -> Bool {
        guard status == .connected else { return false }
        guard let state = control.state else { return control.commands != nil }
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

    // MARK: FCU

    /// Latest raw value behind a binding (array element when it has an index).
    func value(_ binding: FCUBinding?) -> XPValue? {
        guard let binding, let raw = rawValues[binding.dataref] else { return nil }
        return raw.element(at: binding.index)
    }

    func isOn(_ binding: FCUBinding?) -> Bool {
        guard let binding else { return false }
        return binding.isOn(value(binding))
    }

    /// False only when the mapping declares an availability flag and it reads zero.
    var isFCUPowered: Bool {
        guard let available = fcu?.available else { return true }
        guard value(available) != nil else { return true }   // unknown yet: do not blank the panel
        return isOn(available)
    }

    func isAvailable(_ selector: FCUSelectorDefinition) -> Bool {
        guard status == .connected else { return false }
        return !unresolved.contains(selector.value.dataref)
    }

    func isAvailable(_ button: FCUButtonDefinition) -> Bool {
        guard status == .connected else { return false }
        switch button.resolvedKind {
        case .push: return button.command != nil
        case .toggle:
            guard let state = button.state else { return false }
            return !unresolved.contains(state.dataref)
        }
    }

    /// Numeric value currently shown in a selector window, honouring its mode flag.
    func displayedValue(of selector: FCUSelectorDefinition) -> Double? {
        let modeOn = isOn(selector.mode)
        return value(selector.activeValueBinding(modeOn: modeOn))?.doubleValue
    }

    /// Turns a knob `steps` clicks (positive = clockwise / increase). Uses the mapped commands so
    /// ToLiss applies its own increments; falls back to writing the value when there are none.
    func turn(_ selector: FCUSelectorDefinition, steps: Int) {
        guard let client, steps != 0 else { return }
        let increasing = steps > 0
        let command = increasing ? selector.commands?.increase : selector.commands?.decrease
        Task {
            do {
                if let command {
                    for _ in 0..<abs(steps) {
                        try await client.fire(command: command)
                    }
                } else {
                    let modeOn = self.isOn(selector.mode)
                    let format = selector.activeFormat(modeOn: modeOn)
                    let current = self.displayedValue(of: selector) ?? 0
                    var target = current + Double(steps) * format.defaultStep
                    if format.isAngle {
                        target = target.truncatingRemainder(dividingBy: 360)
                        if target < 0 { target += 360 }
                    }
                    if let range = selector.activeRange(modeOn: modeOn) { target = range.clamp(target) }
                    try await client.write(selector.writeBinding.key, XPValue(target))
                }
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    /// Knob pushed in (managed mode).
    func push(_ selector: FCUSelectorDefinition) {
        fireFCU(selector.commands?.push)
    }

    /// Knob pulled out (selected mode).
    func pull(_ selector: FCUSelectorDefinition) {
        fireFCU(selector.commands?.pull)
    }

    /// Direct entry: writes a typed value, clamped to the mapped range. Returns false when the text
    /// is not a number.
    @discardableResult
    func set(_ selector: FCUSelectorDefinition, to text: String) -> Bool {
        guard let client else { return false }
        let modeOn = isOn(selector.mode)
        let format = selector.activeFormat(modeOn: modeOn)
        guard var target = format.parse(text) else { return false }
        if format.isAngle {
            target = target.truncatingRemainder(dividingBy: 360)
            if target < 0 { target += 360 }
        }
        if let range = selector.activeRange(modeOn: modeOn) { target = range.clamp(target) }
        let binding = modeOn && selector.alternateValue != nil ? selector.activeValueBinding(modeOn: true) : selector.writeBinding
        Task {
            do {
                try await client.write(binding.key, XPValue(target))
            } catch {
                self.lastError = self.describe(error)
            }
        }
        return true
    }

    func press(_ button: FCUButtonDefinition) {
        guard let client else { return }
        switch button.resolvedKind {
        case .push:
            fireFCU(button.command)
        case .toggle:
            guard let state = button.state else { return }
            let next = button.nextValue(after: value(state))
            Task {
                do {
                    try await client.write(state.key, XPValue(next))
                } catch {
                    self.lastError = self.describe(error)
                }
            }
        }
    }

    func isLit(_ button: FCUButtonDefinition) -> Bool {
        isOn(button.lit)
    }

    /// Toggle buttons: index of the position currently shown.
    func position(of button: FCUButtonDefinition) -> Int {
        button.position(for: value(button.state)) ?? 0
    }

    private func fireFCU(_ command: String?) {
        guard let client, let command else { return }
        Task {
            do {
                try await client.fire(command: command)
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    // MARK: Diagnostics

    /// Subscribes to an additional dataref for inspection; persists across launches.
    func watch(dataref rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !subscribedDatarefNames.contains(name) else { return }
        extraDatarefs.append(name)
        guard let client, status == .connected else { return }
        Task {
            do {
                let missing = try await client.subscribe(datarefs: [name])
                self.unresolved.formUnion(missing)
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    func unwatch(dataref name: String) {
        extraDatarefs.removeAll { $0 == name }
        rawValues[name] = nil
        unresolved.remove(name)
    }

    func isExtra(_ name: String) -> Bool {
        extraDatarefs.contains(name)
    }

    /// Fires a command by name from the diagnostics screen.
    func fire(command rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let client else { return }
        lastCommandResult = "Enviando \(name)…"
        Task {
            do {
                try await client.fire(command: name)
                self.lastCommandResult = "OK  \(name)"
            } catch {
                self.lastCommandResult = "Error en \(name): \(self.describe(error))"
            }
        }
    }

    func recentlyChanged(_ key: String, within seconds: TimeInterval = 3, now: Date = Date()) -> Bool {
        guard let stamp = changeStamps[key] else { return false }
        return now.timeIntervalSince(stamp) < seconds
    }

    private func describe(_ error: Error) -> String {
        if let xp = error as? XPlaneError, let text = xp.errorDescription { return text }
        return error.localizedDescription
    }
}
