import Foundation
import Observation
import XPlaneKit

/// One thing drawn on the canvas: a generic subpanel, or a panel with its own view (FCU, MCDU).
enum PanelItem: Identifiable {
    case subpanel(SubpanelDefinition)
    case fcu
    case mcdu

    var id: String {
        switch self {
        case .subpanel(let panel): return panel.id
        case .fcu: return "fcu"
        case .mcdu: return "mcdu"
        }
    }
}

/// A panel the user builds by grouping subpanels, the FCU, the MCDU and ECAM controls.
/// Stored on the device (UserDefaults), not in the mapping.
struct CustomPanel: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var icon: String = "square.grid.2x2"
    /// Subpanel ids, "fcu" or "mcdu", in display order.
    var items: [String] = []
    /// Items per row.
    var columns: Int = 2
}

/// Where the integral lighting level of the panels comes from.
enum BacklightMode: String, CaseIterable, Identifiable {
    /// Follow the aircraft's integral lighting knobs (and electrical power).
    case auto
    /// Always lit at the manual level.
    case on
    /// Painted legends only.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Según el avión"
        case .on: return "Siempre"
        case .off: return "Apagada"
        }
    }
}

/// What the main canvas shows: every subpanel, one panel group, or the subpanels of a flight phase.
enum PanelSelection: Hashable {
    case all
    case group(String)
    case phase(String)
    /// One subpanel on its own, fitted to the screen.
    case subpanel(String)
    /// A panel built by the user.
    case custom(String)

    var storageValue: String {
        switch self {
        case .all: return "all"
        case .group(let id): return "group:\(id)"
        case .phase(let id): return "phase:\(id)"
        case .subpanel(let id): return "subpanel:\(id)"
        case .custom(let id): return "custom:\(id)"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    init(storageValue: String) {
        if storageValue.hasPrefix("group:") {
            self = .group(String(storageValue.dropFirst(6)))
        } else if storageValue.hasPrefix("phase:") {
            self = .phase(String(storageValue.dropFirst(6)))
        } else if storageValue.hasPrefix("subpanel:") {
            self = .subpanel(String(storageValue.dropFirst(9)))
        } else if storageValue.hasPrefix("custom:") {
            self = .custom(String(storageValue.dropFirst(7)))
        } else {
            self = .all
        }
    }
}

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
    /// Zoom of the panel canvas (1 = native size). Pinch or the − / + buttons change it.
    var canvasScale: Double {
        didSet { UserDefaults.standard.set(canvasScale, forKey: Keys.scale) }
    }
    /// Bumped by the "fit" button; the canvas answers by choosing the scale that fits its width.
    private(set) var fitRequestID = 0
    /// While true the canvas keeps the selection fitted to the screen (and therefore still):
    /// it refits on rotation, sidebar toggles and selection changes. Manual zoom turns it off,
    /// the fit button turns it back on.
    private(set) var autoFit = true
    /// Wide enough for a single section to fill the screen.
    static let scaleRange: ClosedRange<Double> = 0.3...5.0
    var selection: PanelSelection {
        didSet {
            UserDefaults.standard.set(selection.storageValue, forKey: Keys.selection)
            autoFit = true
        }
    }
    /// Integral lighting of legends and keys.
    var backlightMode: BacklightMode {
        didSet { UserDefaults.standard.set(backlightMode.rawValue, forKey: Keys.backlightMode) }
    }
    /// Level used when the mode is "on", and in "auto" until the aircraft reports its own.
    var backlightManualLevel: Double {
        didSet { UserDefaults.standard.set(backlightManualLevel, forKey: Keys.backlightLevel) }
    }
    /// Integral lighting levels reported by ToLiss, by zone ("overhead", "main", "fcu",
    /// "mcdu1", "mcdu2"). Kept apart from `rawValues` so panels only redraw when these change.
    private(set) var simBacklight: [String: Double] = [:]

    /// ToLiss datarefs that carry the integral lighting levels.
    static let backlightSources = [
        "AirbusFBW/IntegratedLightLevelOHP_Raw",
        "AirbusFBW/IntegratedLightLevelMain_Raw",
        "AirbusFBW/FCUIntegralBrightness",
        "AirbusFBW/MCDUIntegBrightness",
    ]

    /// Panels built by the user, persisted on the device.
    private(set) var customPanels: [CustomPanel] = [] {
        didSet { saveCustomPanels() }
    }
    /// The window is wider than tall. Drives the MCDU's wide layout.
    private(set) var isLandscape = true
    /// MCDU in landscape: keyboard beside the screen (bigger screen) instead of under it.
    var mcduWideInLandscape: Bool {
        didSet {
            UserDefaults.standard.set(mcduWideInLandscape, forKey: Keys.mcduWide)
            layoutRevision += 1
        }
    }
    /// Bumped whenever the canvas content may change size without the selection changing
    /// (orientation, MCDU layout, editing a custom panel), so the canvas measures again.
    private(set) var layoutRevision = 0
    /// MCDU shown in the MCDU view: 1 captain, 2 first officer.
    private(set) var mcduUnit: Int {
        didSet { UserDefaults.standard.set(mcduUnit, forKey: Keys.mcduUnit) }
    }
    /// Raw MCDU screen datarefs, kept apart from `rawValues` so ~150 text updates per page change
    /// do not re-render every switch on the overhead.
    private(set) var mcduRaw: [String: XPValue] = [:]
    /// Datarefs added from the diagnostics screen, on top of the ones the mapping needs.
    private(set) var extraDatarefs: [String] {
        didSet { UserDefaults.standard.set(extraDatarefs, forKey: Keys.extras) }
    }

    private(set) var status: Status = .disconnected
    private(set) var subpanels: [SubpanelDefinition] = []
    private(set) var layout: PanelLayout = .empty
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
        // v2: badges are off by default since the overhead aims at realism; mapping work turns them on.
        static let badges = "ui.verificationBadges.v2"
        static let extras = "diag.extraDatarefs"
        static let selection = "ui.selection"
        static let scale = "ui.canvasScale"
        static let mcduUnit = "mcdu.unit"
        static let mcduWide = "mcdu.wideInLandscape"
        static let customPanels = "custom.panels"
        static let backlightMode = "ui.backlightMode"
        static let backlightLevel = "ui.backlightLevel"
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: Keys.host) ?? "192.168.1.100"
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort == 0 ? 8087 : storedPort   // 8087 = xp_relay.py default
        showVerificationBadges = defaults.object(forKey: Keys.badges) as? Bool ?? false
        extraDatarefs = defaults.stringArray(forKey: Keys.extras) ?? []
        let storedUnit = defaults.integer(forKey: Keys.mcduUnit)
        mcduUnit = storedUnit == 2 ? 2 : 1
        mcduWideInLandscape = defaults.object(forKey: Keys.mcduWide) as? Bool ?? true
        backlightMode = BacklightMode(rawValue: defaults.string(forKey: Keys.backlightMode) ?? "") ?? .auto
        backlightManualLevel = defaults.object(forKey: Keys.backlightLevel) as? Double ?? 0.75
        if let data = defaults.data(forKey: Keys.customPanels),
           let stored = try? JSONDecoder().decode([CustomPanel].self, from: data) {
            customPanels = stored
        }
        selection = PanelSelection(storageValue: defaults.string(forKey: Keys.selection) ?? "group:overhead")
        let storedScale = defaults.double(forKey: Keys.scale)
        canvasScale = storedScale == 0 ? 0.8 : min(max(storedScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        fitRequestID = 1   // launch fitted: the panel starts still
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
            layout = try PanelLoader.loadLayout(in: directory)
        } catch {
            lastError = "Error leyendo mapping: \(error.localizedDescription)"
        }
        let fcuDirectory = directory.appendingPathComponent("fcu", isDirectory: true)
        if FileManager.default.fileExists(atPath: fcuDirectory.path) {
            do {
                fcu = try FCULoader.loadFirst(in: fcuDirectory)
            } catch {
                lastError = "Error leyendo mapping/fcu: \(error.localizedDescription)"
            }
        }
    }

    /// What the canvas shows for the current sidebar selection, in display order.
    /// The FCU and the MCDU are addressed by the ids "fcu" and "mcdu" in groups and phases.
    var visibleItems: [PanelItem] {
        let fcuItem: [PanelItem] = fcu == nil ? [] : [.fcu]
        let mcduItem: [PanelItem] = hasMCDU ? [.mcdu] : []
        func special(_ id: String) -> [PanelItem]? {
            switch id {
            case "fcu": return fcuItem
            case "mcdu": return mcduItem
            default: return nil
            }
        }
        switch selection {
        case .all:
            return subpanels.map { .subpanel($0) } + fcuItem + mcduItem
        case .group(let id):
            if let items = special(id) { return items }
            return subpanels.filter { $0.groupID == id }.map { .subpanel($0) }
        case .phase(let id):
            guard let phase = layout.phases.first(where: { $0.id == id }) else { return [] }
            return phase.subpanels.flatMap { wanted -> [PanelItem] in
                if let items = special(wanted) { return items }
                return subpanels.first { $0.id == wanted }.map { [.subpanel($0)] } ?? []
            }
        case .subpanel(let id):
            if let items = special(id) { return items }
            return subpanels.first { $0.id == id }.map { [.subpanel($0)] } ?? []
        case .custom(let id):
            guard let panel = customPanels.first(where: { $0.id == id }) else { return [] }
            return panel.items.flatMap { wanted -> [PanelItem] in
                if let items = special(wanted) { return items }
                return subpanels.first { $0.id == wanted }.map { [.subpanel($0)] } ?? []
            }
        }
    }

    // MARK: Custom panels

    var selectedCustomPanel: CustomPanel? {
        guard case .custom(let id) = selection else { return nil }
        return customPanels.first { $0.id == id }
    }

    struct CatalogItem: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct CatalogGroup: Identifiable {
        let id: String
        let title: String
        let items: [CatalogItem]
    }

    /// Everything that can go into a custom panel: built-in panels first, then each group's
    /// sections in reading order.
    var customPanelCatalog: [CatalogGroup] {
        var catalog: [CatalogGroup] = []
        var builtIn: [CatalogItem] = []
        if fcu != nil { builtIn.append(CatalogItem(id: "fcu", title: "FCU")) }
        if hasMCDU { builtIn.append(CatalogItem(id: "mcdu", title: "MCDU")) }
        if !builtIn.isEmpty { catalog.append(CatalogGroup(id: "builtin", title: "Paneles completos", items: builtIn)) }
        for group in layout.groups {
            let sections = self.sections(of: group.id).map { CatalogItem(id: $0.id, title: displayTitle(of: $0)) }
            if !sections.isEmpty { catalog.append(CatalogGroup(id: group.id, title: group.title, items: sections)) }
        }
        return catalog
    }

    func isSaved(_ panel: CustomPanel) -> Bool {
        customPanels.contains { $0.id == panel.id }
    }

    func displayTitle(of panel: SubpanelDefinition) -> String {
        panel.title.isEmpty ? panel.id.replacingOccurrences(of: "_", with: " ").uppercased()
                            : panel.title.replacingOccurrences(of: "\n", with: " ")
    }

    func title(ofItem id: String) -> String {
        switch id {
        case "fcu": return "FCU"
        case "mcdu": return "MCDU"
        default: return subpanels.first { $0.id == id }.map(displayTitle(of:)) ?? id
        }
    }

    /// Adds or replaces a custom panel and shows it.
    func save(_ panel: CustomPanel) {
        var cleaned = panel
        cleaned.title = panel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.title.isEmpty { cleaned.title = "Mi panel" }
        cleaned.columns = min(max(panel.columns, 1), 4)
        if let index = customPanels.firstIndex(where: { $0.id == panel.id }) {
            customPanels[index] = cleaned
        } else {
            customPanels.append(cleaned)
        }
        layoutRevision += 1
        selection = .custom(cleaned.id)
    }

    func deleteCustomPanel(_ id: String) {
        customPanels.removeAll { $0.id == id }
        if case .custom(let selected) = selection, selected == id {
            selection = .group("overhead")
        }
    }

    func moveCustomPanels(from source: IndexSet, to destination: Int) {
        customPanels.move(fromOffsets: source, toOffset: destination)
    }

    /// A new custom panel seeded with a phase's subpanels, so a phase can be tailored.
    func customPanel(fromPhase id: String) -> CustomPanel? {
        guard let phase = layout.phases.first(where: { $0.id == id }) else { return nil }
        return CustomPanel(title: "\(phase.title) (mío)", icon: phase.icon ?? "square.grid.2x2",
                           items: phase.subpanels, columns: 2)
    }

    private func saveCustomPanels() {
        if let data = try? JSONEncoder().encode(customPanels) {
            UserDefaults.standard.set(data, forKey: Keys.customPanels)
        }
    }

    // MARK: Integral lighting

    /// Level (0…1) of the integral lighting for a panel group or built-in panel id.
    func backlight(forGroup group: String) -> Double {
        switch backlightMode {
        case .off: return 0
        case .on: return backlightManualLevel
        case .auto:
            let zone: String
            switch group {
            case "overhead": zone = "overhead"
            case "fcu": zone = "fcu"
            case "mcdu": zone = "mcdu\(mcduUnit)"
            default: zone = "main"          // pedestal, ECAM, glareshield
            }
            return status == .connected ? (simBacklight[zone] ?? backlightManualLevel) : backlightManualLevel
        }
    }

    private func applyBacklight(_ update: DatarefUpdate) {
        func store(_ zone: String, _ value: Double?) {
            guard let value else { return }
            let level = min(max(value, 0), 1)
            if abs((simBacklight[zone] ?? -1) - level) > 0.02 { simBacklight[zone] = level }
        }
        switch update.name {
        case "AirbusFBW/IntegratedLightLevelOHP_Raw": store("overhead", update.value.doubleValue)
        case "AirbusFBW/IntegratedLightLevelMain_Raw": store("main", update.value.doubleValue)
        case "AirbusFBW/FCUIntegralBrightness": store("fcu", update.value.doubleValue)
        case "AirbusFBW/MCDUIntegBrightness":
            store("mcdu1", update.value.element(at: 0)?.doubleValue)
            store("mcdu2", update.value.element(at: 1)?.doubleValue)
        default: break
        }
    }

    // MARK: Orientation

    func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        layoutRevision += 1
    }

    // MARK: MCDU

    /// The MCDU is built in (no mapping file): it is on when layout.json declares a "mcdu" group.
    var hasMCDU: Bool {
        layout.groups.contains { $0.id == "mcdu" }
    }

    /// Decoded screen of the selected MCDU.
    var mcduScreen: MCDUScreen {
        MCDUScreen.decode(unit: mcduUnit, values: mcduRaw)
    }

    /// Switches between the captain's (1) and first officer's (2) MCDU.
    func setMCDUUnit(_ unit: Int) {
        guard unit == 1 || unit == 2, unit != mcduUnit else { return }
        mcduUnit = unit
        guard let client, status == .connected else { return }
        Task {
            do {
                _ = try await client.subscribe(datarefs: MCDUScreen.datarefNames(unit: unit))
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    /// Presses an MCDU key: `key` is the ToLiss command suffix, e.g. "LSK1L", "KeyA", "DirTo".
    func pressMCDU(_ key: String, duration: Double = 0) {
        guard let client, status == .connected else { return }
        let command = "AirbusFBW/MCDU\(mcduUnit)\(key)"
        Task {
            do {
                try await client.fire(command: command, duration: duration)
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    /// Subpanels of a group for the sidebar's section list, in reading order (top-left first).
    func sections(of group: String) -> [SubpanelDefinition] {
        // Column (left / centre / right third of the group's canvas) from the frame's centre,
        // then top to bottom: captain side first, as you read the panel.
        let width = layout.canvas(for: group)?.width ?? 828
        func column(_ panel: SubpanelDefinition) -> Int {
            guard let frame = panel.frame else { return 9 }
            return min(Int((frame.x + frame.w / 2) / (width / 3)), 2)
        }
        return subpanels.filter { $0.groupID == group }.sorted {
            let ca = column($0), cb = column($1)
            if ca != cb { return ca < cb }
            let ya = $0.frame?.y ?? Double($0.order ?? 0), yb = $1.frame?.y ?? Double($1.order ?? 0)
            if ya != yb { return ya < yb }
            return ($0.frame?.x ?? 0) < ($1.frame?.x ?? 0)
        }
    }


    func zoom(by factor: Double) {
        autoFit = false
        canvasScale = min(max(canvasScale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    /// Pinch in progress: manual zoom, so stop refitting.
    func pinch(to value: Double) {
        autoFit = false
        setScale(value)
    }

    func requestFit() {
        autoFit = true
        fitRequestID += 1
    }

    func setScale(_ value: Double) {
        canvasScale = min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    /// Faded controls: candidates locked as read-only, or datarefs this aircraft does not expose.
    /// Being disconnected does not dim the panel; it only disables interaction.
    func isDimmed(_ control: ControlDefinition) -> Bool {
        if control.isReadOnly { return true }
        if let state = control.state, unresolved.contains(state.dataref) { return true }
        return false
    }

    /// Subpanels of a group that are visible now, keyed by id.
    func visibleSubpanels(in group: String) -> [String: SubpanelDefinition] {
        var result: [String: SubpanelDefinition] = [:]
        for case .subpanel(let panel) in visibleItems where panel.groupID == group {
            result[panel.id] = panel
        }
        return result
    }

    var selectionTitle: String {
        switch selection {
        case .all: return "Todos los paneles"
        case .group(let id): return layout.groups.first { $0.id == id }?.title ?? id
        case .phase(let id): return layout.phases.first { $0.id == id }?.title ?? id
        case .subpanel(let id):
            return title(ofItem: id)
        case .custom(let id):
            return customPanels.first { $0.id == id }?.title ?? "Panel"
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
        if hasMCDU { names.formUnion(MCDUScreen.datarefNames(unit: mcduUnit)) }
        names.formUnion(Self.backlightSources)
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
        if Self.backlightSources.contains(update.name) {
            applyBacklight(update)
        }
        if update.name.hasPrefix("AirbusFBW/MCDU1") || update.name.hasPrefix("AirbusFBW/MCDU2") {
            mcduRaw[update.name] = update.value
            return
        }
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
        guard status == .connected, !control.isReadOnly else { return false }
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
                        try await client.fire(command: command, duration: control.commands?.duration ?? 0)
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

    /// Pushbutton press: fires `press`, or `up`/`down` (on/off) from the current state,
    /// or cycles the bound value.
    func press(_ control: ControlDefinition) {
        guard let client else { return }
        let count = max(control.positions.count, 2)
        let current = position(of: control)
        let next = (current + 1) % count
        let duration = control.commands?.duration ?? 0
        Task {
            do {
                if let command = control.commands?.press {
                    try await client.fire(command: command, duration: duration)
                } else if let on = control.commands?.up, let off = control.commands?.down {
                    try await client.fire(command: current == 0 ? on : off, duration: duration)
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

    /// Dual knob: one click of the outer (`small` false) or inner ring, `delta` > 0 clockwise.
    func turn(_ control: ControlDefinition, small: Bool, delta: Int) {
        guard let client, delta != 0, let commands = control.commands else { return }
        let name = small ? (delta > 0 ? commands.upSmall : commands.downSmall)
                         : (delta > 0 ? commands.up : commands.down)
        guard let name else { return }
        Task {
            do {
                for _ in 0..<abs(delta) {
                    try await client.fire(command: name)
                }
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    /// Knob: 0…1 over the control's range from the raw dataref value.
    func fraction(of control: ControlDefinition) -> Double {
        guard let state = control.state, let range = control.range,
              let raw = rawValues[state.dataref]?.element(at: state.index)?.doubleValue else { return 0 }
        return range.fraction(of: raw)
    }

    /// Knob: writes the raw value for a 0…1 fraction.
    func set(_ control: ControlDefinition, fraction: Double) {
        guard let client, let binding = control.writeBinding, let range = control.range else { return }
        let target = range.value(at: fraction)
        Task {
            do {
                try await client.write(binding.key, XPValue(target))
            } catch {
                self.lastError = self.describe(error)
            }
        }
    }

    /// Display: formatted raw value. Without a format it is a legend window that shows the last
    /// position name when the value is on (ADIRS "ON BAT"). Dashes when unknown.
    func displayText(of control: ControlDefinition) -> String {
        if control.format == "text" {
            guard let state = control.state, let raw = rawValues[state.dataref] else { return "" }
            return raw.textValue ?? ""
        }
        guard let state = control.state,
              let raw = rawValues[state.dataref]?.element(at: state.index)?.doubleValue else {
            return (control.format ?? "").isEmpty ? "" : "--.-"
        }
        if let format = control.format, !format.isEmpty {
            return String(format: format, raw)
        }
        return raw > 0.5 ? (control.positions.last ?? "ON") : ""
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
