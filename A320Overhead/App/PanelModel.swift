import Foundation
import Observation
import XPlaneKit

/// One thing drawn on the canvas: a generic subpanel, or a panel with its own view (FCU, MCDU).
enum PanelItem: Identifiable {
    case subpanel(SubpanelDefinition)
    case fcu
    case mcdu
    /// Camera views: X-Plane quick looks and the X-Camera commands found in the simulator.
    case camera

    var id: String {
        switch self {
        case .subpanel(let panel): return panel.id
        case .fcu: return "fcu"
        case .mcdu: return "mcdu"
        case .camera: return "camera"
        }
    }
}

/// A panel the user builds by grouping subpanels, the FCU, the MCDU and ECAM controls.
/// Stored on the device (UserDefaults), not in the mapping.
struct CustomPanel: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var icon: String = "square.grid.2x2"
    /// Subpanel ids, "fcu", "mcdu" or "camera", in display order.
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
/// One run of an exercise: the tracker while it is flown, then its result.
struct ExerciseRun {
    var tracker: ExerciseTracker
    let startedAt: Date
    /// Set when the run ends; the result sheet shows it.
    var result: ExerciseResult?
    /// Exam mode: steps revealed with the hint button.
    var revealed: Set<Int> = []

    var isRunning: Bool { result == nil }
}

enum PanelSelection: Hashable {
    case all
    case group(String)
    case phase(String)
    /// One subpanel on its own, fitted to the screen.
    case subpanel(String)
    /// A panel built by the user.
    case custom(String)
    /// The panels a flow or checklist works on, with the checklist beside them.
    case procedure(String)

    var storageValue: String {
        switch self {
        case .all: return "all"
        case .group(let id): return "group:\(id)"
        case .phase(let id): return "phase:\(id)"
        case .subpanel(let id): return "subpanel:\(id)"
        case .custom(let id): return "custom:\(id)"
        case .procedure(let id): return "procedure:\(id)"
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
        } else if storageValue.hasPrefix("procedure:") {
            self = .procedure(String(storageValue.dropFirst(10)))
        } else {
            self = .all
        }
    }
}

/// Single source of truth for the UI: connection status, loaded subpanels and the live
/// position of every control. Owns the connection (`XPlaneClient`, or
/// `DemoSimulator` in demo mode) and its update streams.
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
    /// Demo mode: the panel runs against `DemoSimulator` instead of X-Plane, to try it without a
    /// simulator. Changing it while connected reconnects in the new mode.
    var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: Keys.demoMode)
            if demoMode != oldValue, status.isActive { connect() }
        }
    }
    var showVerificationBadges: Bool {
        didSet { UserDefaults.standard.set(showVerificationBadges, forKey: Keys.badges) }
    }
    /// How long the demo's systems take (APU, ADIRS, engine start): real time, a fifth, or instant.
    var demoTiming: DemoTiming {
        didSet {
            UserDefaults.standard.set(demoTiming.rawValue, forKey: Keys.demoTiming)
            if let demo = client as? DemoSimulator {
                let timing = demoTiming
                Task { await demo.setTiming(timing) }
            }
        }
    }
    /// What the demo reports about its systems (power, APU, IRS, engines); nil outside the demo.
    private(set) var demoSystems: DemoSystemsStatus?
    /// The demo's power level alone: lamps and windows read this, so they only redraw when the
    /// power changes, not on every progress tick of the summary.
    private(set) var demoPower: DemoSystemsStatus.Power?
    /// Learn mode: touching a control explains it instead of moving it.
    var learnMode: Bool {
        didSet { UserDefaults.standard.set(learnMode, forKey: Keys.learnMode) }
    }
    /// Control whose explanation sheet is open (panel control id, FCU id or "mcdu.<key>").
    var explainingControlID: String?
    /// Explanations of systems and controls from `mapping/guide`.
    private(set) var guide: Guide = .empty
    /// Timed exercises from `mapping/exercises`.
    private(set) var exercises: [ExerciseDefinition] = []
    /// The exercise being flown, and its result once it ends.
    private(set) var exerciseRun: ExerciseRun?
    /// Results by exercise id, newest first.
    private(set) var exerciseResults: [String: [ExerciseResult]] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(exerciseResults) {
                UserDefaults.standard.set(data, forKey: Keys.exerciseResults)
            }
        }
    }
    /// Exercise whose briefing sheet is open.
    var exerciseBriefingID: String?
    /// Switches whose position matters: every overhead control and any control a procedure
    /// checks. Moving one an exercise does not use is a mistake; radios, keypads and display
    /// keys are not judged.
    @ObservationIgnored private var configurationControls: Set<String> = []
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
            if case .procedure(let id) = selection {
                activeProcedureID = id
                showChecklist = true
            }
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

    /// Flows and checklists from `mapping/procedures`, in flight order.
    private(set) var procedures: [Procedure] = []
    /// Items ticked by hand, keyed "procedureID#itemIndex". Sensed items tick themselves.
    private(set) var manualChecks: Set<String> {
        didSet { UserDefaults.standard.set(Array(manualChecks), forKey: Keys.checks) }
    }
    /// Procedure shown in the checklist column.
    private(set) var activeProcedureID: String? {
        didSet { UserDefaults.standard.set(activeProcedureID, forKey: Keys.activeProcedure) }
    }
    /// The checklist column beside the panels is open.
    var showChecklist: Bool {
        didSet { UserDefaults.standard.set(showChecklist, forKey: Keys.showChecklist) }
    }
    /// Control pointed at from a checklist item; it pulses for a moment.
    private(set) var highlightedControl: String?
    /// Radio panel (RMP) whose tuner is open.
    var tuningRadioID: String?
    private(set) var tuning: TuningState = .idle
    /// Last frequencies tuned from the tuner, newest first, in kHz.
    private(set) var recentFrequencies: [Int] {
        didSet { UserDefaults.standard.set(recentFrequencies, forKey: Keys.recentFrequencies) }
    }
    @ObservationIgnored private var tuningTask: Task<Void, Never>?
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    /// Control id → definition and → subpanel id, built once from the mapping.
    @ObservationIgnored private var controlsByID: [String: ControlDefinition] = [:]
    @ObservationIgnored private var panelOfControl: [String: String] = [:]

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

    @ObservationIgnored private var client: (any SimulatorConnection)?
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var connectGeneration = 0

    private enum Keys {
        static let host = "xp.host"
        static let port = "xp.port"
        static let demoMode = "xp.demoMode"
        static let demoTiming = "xp.demoTiming"
        // v2: badges are off by default since the overhead aims at realism; mapping work turns them on.
        static let badges = "ui.verificationBadges.v2"
        static let learnMode = "ui.learnMode"
        static let exerciseResults = "exercises.results"
        static let extras = "diag.extraDatarefs"
        static let selection = "ui.selection"
        static let scale = "ui.canvasScale"
        static let mcduUnit = "mcdu.unit"
        static let mcduWide = "mcdu.wideInLandscape"
        static let customPanels = "custom.panels"
        static let backlightMode = "ui.backlightMode"
        static let backlightLevel = "ui.backlightLevel"
        static let checks = "procedures.checks"
        static let activeProcedure = "procedures.active"
        static let showChecklist = "procedures.showChecklist"
        static let recentFrequencies = "radio.recentFrequencies"
        static let xCamera = "camera.xCameraCommands"
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: Keys.host) ?? "192.168.1.100"
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort == 0 ? 8087 : storedPort   // 8087 = xp_relay.py default
        demoMode = defaults.bool(forKey: Keys.demoMode)
        demoTiming = DemoTiming(rawValue: defaults.string(forKey: Keys.demoTiming) ?? "") ?? .realistic
        showVerificationBadges = defaults.object(forKey: Keys.badges) as? Bool ?? false
        learnMode = defaults.bool(forKey: Keys.learnMode)
        if let data = defaults.data(forKey: Keys.exerciseResults),
           let stored = try? JSONDecoder().decode([String: [ExerciseResult]].self, from: data) {
            exerciseResults = stored
        }
        extraDatarefs = defaults.stringArray(forKey: Keys.extras) ?? []
        let storedUnit = defaults.integer(forKey: Keys.mcduUnit)
        mcduUnit = storedUnit == 2 ? 2 : 1
        mcduWideInLandscape = defaults.object(forKey: Keys.mcduWide) as? Bool ?? true
        backlightMode = BacklightMode(rawValue: defaults.string(forKey: Keys.backlightMode) ?? "") ?? .auto
        backlightManualLevel = defaults.object(forKey: Keys.backlightLevel) as? Double ?? 0.75
        manualChecks = Set(defaults.stringArray(forKey: Keys.checks) ?? [])
        activeProcedureID = defaults.string(forKey: Keys.activeProcedure)
        showChecklist = defaults.bool(forKey: Keys.showChecklist)
        recentFrequencies = (defaults.array(forKey: Keys.recentFrequencies) as? [Int]) ?? []
        xCameraCommands = defaults.data(forKey: Keys.xCamera)
            .flatMap { try? JSONDecoder().decode([CameraCommand].self, from: $0) } ?? []
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
        for panel in subpanels {
            for control in panel.controls {
                controlsByID[control.id] = control
                panelOfControl[control.id] = panel.id
            }
        }
        let proceduresDirectory = directory.appendingPathComponent("procedures", isDirectory: true)
        if FileManager.default.fileExists(atPath: proceduresDirectory.path) {
            do {
                procedures = try ProcedureLoader.loadAll(in: proceduresDirectory)
            } catch {
                lastError = "Error leyendo mapping/procedures: \(error.localizedDescription)"
            }
        }
        let guideDirectory = directory.appendingPathComponent("guide", isDirectory: true)
        if FileManager.default.fileExists(atPath: guideDirectory.path) {
            do {
                guide = try GuideLoader.load(in: guideDirectory)
            } catch {
                lastError = "Error leyendo mapping/guide: \(error.localizedDescription)"
            }
        }
        let exercisesDirectory = directory.appendingPathComponent("exercises", isDirectory: true)
        if FileManager.default.fileExists(atPath: exercisesDirectory.path) {
            do {
                exercises = try ExerciseLoader.loadAll(in: exercisesDirectory)
            } catch {
                lastError = "Error leyendo mapping/exercises: \(error.localizedDescription)"
            }
        }
        configurationControls = Set(subpanels.filter { $0.groupID == "overhead" }.flatMap { $0.controls.map(\.id) })
            .union(procedures.flatMap { $0.items.flatMap { ($0.checks ?? []).map(\.control) } })
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
        let cameraItem: [PanelItem] = hasCamera ? [.camera] : []
        func special(_ id: String) -> [PanelItem]? {
            switch id {
            case "fcu": return fcuItem
            case "mcdu": return mcduItem
            case "camera": return cameraItem
            default: return nil
            }
        }
        switch selection {
        case .all:
            return subpanels.map { .subpanel($0) } + fcuItem + mcduItem + cameraItem
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
        case .procedure(let id):
            return panelIDs(forProcedure: id).flatMap { wanted -> [PanelItem] in
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
        if hasCamera { builtIn.append(CatalogItem(id: "camera", title: "Cámaras")) }
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
        case "camera": return "Cámaras"
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

    // MARK: Procedures

    func procedure(_ id: String?) -> Procedure? {
        guard let id else { return nil }
        return procedures.first { $0.id == id }
    }

    /// The procedure in the checklist column; the first one until the user picks another.
    var activeProcedure: Procedure? {
        procedure(activeProcedureID) ?? procedures.first
    }

    /// Panels a procedure works on; a procedure without any shows its flight phase.
    func panelIDs(forProcedure id: String) -> [String] {
        guard let procedure = procedure(id) else { return [] }
        let ids = procedure.panels { self.panelOfControl[$0] }
        if !ids.isEmpty { return ids }
        return layout.phases.first { $0.id == procedure.phase }?.subpanels ?? []
    }

    /// Opens a procedure in the checklist column. While the canvas shows a procedure's panels it
    /// follows; any other panel the user chose stays on screen.
    func open(procedure id: String) {
        activeProcedureID = id
        showChecklist = true
        if case .procedure = selection { selection = .procedure(id) }
    }

    /// Controls of a sensed item that are not where the item wants them, as "LABEL: POSITION".
    func mismatches(in item: ProcedureItem) -> [String] {
        (item.checks ?? []).compactMap { check in
            guard let current = positionName(ofControl: check.control), !check.expect.contains(current),
                  let control = controlsByID[check.control] else { return nil }
            let label = control.label.replacingOccurrences(of: "\n", with: " ")
            return "\(label.isEmpty ? check.control : label): \(current.isEmpty ? "—" : current)"
        }
    }

    /// The control to point at for an item: the first one out of place, else the first checked.
    func controlToLocate(for item: ProcedureItem) -> String? {
        let checks = item.checks ?? []
        return checks.first { check in
            positionName(ofControl: check.control).map { !check.expect.contains($0) } ?? false
        }?.control ?? checks.first?.control
    }

    func next(after procedure: Procedure) -> Procedure? {
        guard let index = procedures.firstIndex(of: procedure), index + 1 < procedures.count else { return nil }
        return procedures[index + 1]
    }

    /// Current position name of a control, nil while it is unknown or the sim is not connected.
    func positionName(ofControl id: String) -> String? {
        guard status == .connected, let control = controlsByID[id],
              let index = positions[id], control.positions.indices.contains(index) else { return nil }
        return control.positions[index]
    }

    func sensedState(of item: ProcedureItem) -> ProcedureCheckState {
        item.sensedState(position: positionName(ofControl:))
    }

    private func checkKey(_ procedure: Procedure, _ index: Int) -> String {
        "\(procedure.id)#\(index)"
    }

    func isTicked(_ procedure: Procedure, item index: Int) -> Bool {
        manualChecks.contains(checkKey(procedure, index))
    }

    func isDone(_ procedure: Procedure, item index: Int) -> Bool {
        guard procedure.items.indices.contains(index) else { return false }
        return isTicked(procedure, item: index) || sensedState(of: procedure.items[index]) == .satisfied
    }

    func toggleTick(_ procedure: Procedure, item index: Int) {
        let key = checkKey(procedure, index)
        if manualChecks.contains(key) { manualChecks.remove(key) } else { manualChecks.insert(key) }
        refreshExercise()
    }

    func progress(of procedure: Procedure) -> (done: Int, total: Int) {
        (procedure.items.indices.filter { isDone(procedure, item: $0) }.count, procedure.items.count)
    }

    func isComplete(_ procedure: Procedure) -> Bool {
        let progress = progress(of: procedure)
        return progress.total > 0 && progress.done == progress.total
    }

    /// First item still to do: the one the checklist column frames.
    func currentItem(in procedure: Procedure) -> Int? {
        procedure.items.indices.first { !isDone(procedure, item: $0) }
    }

    func resetTicks(of procedure: Procedure) {
        manualChecks = manualChecks.filter { !$0.hasPrefix("\(procedure.id)#") }
    }

    /// Every procedure of a flight phase.
    func resetTicks(ofPhase phase: String) {
        for procedure in procedures where (procedure.phase ?? "other") == phase {
            resetTicks(of: procedure)
        }
    }

    /// The demo can also put the switches back, so sensed items start again too.
    var canResetAircraft: Bool { client is DemoSimulator && status == .connected }

    /// Demo: back to cold and dark. The new values are applied before returning, so whatever
    /// runs next (a checklist, an exercise) reads the reset aircraft.
    func resetDemoAircraft() async {
        guard let demo = client as? DemoSimulator else { return }
        let updates = await demo.resetAircraft()
        for update in updates { apply(update) }
        // Let updates already queued before the reset go through the listener first.
        try? await Task.sleep(for: .milliseconds(300))
        for update in updates { apply(update) }
    }

    /// Clears hand ticks and, in the demo, also the aircraft.
    func resetProcedures(_ list: [Procedure], aircraft: Bool) {
        list.forEach(resetTicks(of:))
        if aircraft { Task { await resetDemoAircraft() } }
    }

    func resetAllTicks() {
        manualChecks = []
    }

    /// Shows the control an item refers to: switches to its section when it is not on screen,
    /// then makes it pulse.
    func locate(control id: String) {
        exerciseHint()
        highlight(control: id)
    }

    private func highlight(control id: String) {
        guard let panel = panelOfControl[id] else { return }
        if !visibleItems.contains(where: { $0.id == panel }) { selection = .subpanel(panel) }
        highlightedControl = id
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, self?.highlightedControl == id else { return }
            self?.highlightedControl = nil
        }
    }

    /// Shows a panel an item refers to (MCDU, FCU, a section) when it is not on screen.
    func locate(panel id: String) {
        if !visibleItems.contains(where: { $0.id == id }) { selection = .subpanel(id) }
    }

    /// The sensed controls can be moved to the expected positions from the checklist.
    func canApply(_ item: ProcedureItem) -> Bool {
        guard sensedState(of: item) == .unsatisfied else { return false }
        return (item.checks ?? []).allSatisfy { check in
            controlsByID[check.control].map { isAvailable($0) } ?? false
        }
    }

    /// Moves every sensed control that is out of place to the first expected position.
    func apply(_ item: ProcedureItem) {
        exerciseHint()
        for check in item.checks ?? [] {
            guard let control = controlsByID[check.control], isAvailable(control),
                  let current = positionName(ofControl: check.control), !check.expect.contains(current),
                  let wanted = check.expect.first, let target = control.positions.firstIndex(of: wanted) else { continue }
            let delta = target - position(of: control)
            switch control.kind {
            case .korry:
                press(control)
            default:
                move(control, by: delta)
            }
        }
    }

    // MARK: Learn mode

    /// Opens the explanation sheet of a control.
    func explain(control id: String) {
        explainingControlID = id
    }

    func hasExplanation(_ id: String) -> Bool {
        guide.explanation(for: id) != nil
    }

    func control(withID id: String) -> ControlDefinition? {
        controlsByID[id]
    }

    /// Subpanel id of a control: its mapping file, or "fcu" / "mcdu" for those units.
    func panelID(ofControl id: String) -> String? {
        if let panel = panelOfControl[id] { return panel }
        if fcu?.selectors.contains(where: { $0.id == id }) == true || fcu?.buttons.contains(where: { $0.id == id }) == true {
            return "fcu"
        }
        return id.hasPrefix("mcdu.") ? "mcdu" : nil
    }

    func system(ofControl id: String) -> SystemGuide? {
        panelID(ofControl: id).flatMap { guide.system(forPanel: $0) }
    }

    /// Procedures that move or check a control, in flight order. FCU and MCDU controls are not
    /// sensed, so for them it is the procedures that bring up their unit.
    func proceduresUsing(control id: String) -> [Procedure] {
        let unit = panelID(ofControl: id).flatMap { $0 == "fcu" || $0 == "mcdu" ? $0 : nil }
        return procedures.filter { procedure in
            procedure.items.contains { item in
                if (item.checks ?? []).contains(where: { $0.control == id }) { return true }
                if let unit { return (item.panels ?? []).contains(unit) }
                return false
            }
        }
    }

    // MARK: Exercises

    var isExerciseRunning: Bool { exerciseRun?.isRunning == true }
    var isExamRunning: Bool { isExerciseRunning && exerciseRun?.tracker.mode == .exam }

    func exercise(_ id: String?) -> ExerciseDefinition? {
        guard let id else { return nil }
        return exercises.first { $0.id == id }
    }

    func bestResult(of id: String) -> ExerciseResult? {
        exerciseResults[id]?.max { $0.score < $1.score }
    }

    /// Steps an exercise has in a mode, for its briefing.
    func exerciseSteps(_ definition: ExerciseDefinition, mode: ExerciseMode) -> [ExerciseStep] {
        ExerciseTracker(definition: definition, procedures: procedures, mode: mode).steps
    }

    /// Starts a run: clears the hand ticks of its procedures, records the starting state and
    /// shows the first procedure (guided) or its flight phase without the checklist (exam).
    func startExercise(_ id: String, mode: ExerciseMode) {
        guard status == .connected, let definition = exercise(id) else { return }
        for procedureID in definition.procedures {
            if let found = procedure(procedureID) { resetTicks(of: found) }
        }
        learnMode = false
        exerciseBriefingID = nil
        var tracker = ExerciseTracker(definition: definition, procedures: procedures, mode: mode)
        tracker.update(at: 0, position: positionName(ofControl:), ticked: isTicked(step:))
        exerciseRun = ExerciseRun(tracker: tracker, startedAt: Date())
        guard let first = definition.procedures.first else { return }
        switch mode {
        case .guided:
            selection = .procedure(first)
        case .exam:
            showChecklist = false
            if let phase = procedure(first)?.phase { selection = .phase(phase) }
        }
    }

    func abandonExercise() {
        exerciseRun = nil
    }

    /// Closes the result sheet.
    func closeExerciseResult() {
        exerciseRun = nil
    }

    /// Starts again the current or just finished exercise; in the demo, optionally from cold
    /// and dark.
    func repeatExercise(fromColdAndDark: Bool = false) {
        guard let run = exerciseRun else { return }
        exerciseRun = nil
        beginExercise(run.tracker.definition.id, mode: run.tracker.mode, fromColdAndDark: fromColdAndDark)
    }

    /// `startExercise`, after resetting the demo aircraft when asked.
    func beginExercise(_ id: String, mode: ExerciseMode, fromColdAndDark: Bool) {
        guard fromColdAndDark, canResetAircraft else {
            startExercise(id, mode: mode)
            return
        }
        exerciseBriefingID = nil
        Task {
            await resetDemoAircraft()
            startExercise(id, mode: mode)
        }
    }

    /// Deletes the stored results of one exercise, or of all with nil.
    func deleteResults(of id: String?) {
        if let id {
            exerciseResults[id] = nil
        } else {
            exerciseResults = [:]
        }
    }

    /// Exam mode: shows the next step and points at its control, at the price of a hint.
    func revealExerciseStep() {
        guard var run = exerciseRun, run.isRunning, let current = run.tracker.currentStep else { return }
        run.revealed.insert(current)
        run.tracker.useHint()
        exerciseRun = run
        if let control = run.tracker.steps[current].item.checks?.first?.control {
            highlight(control: control)
        }
    }

    func exerciseElapsed(at date: Date = Date()) -> Double {
        guard let run = exerciseRun else { return 0 }
        return run.result?.elapsed ?? date.timeIntervalSince(run.startedAt)
    }

    /// One line for a mistake, in the result sheet and the exercise bar.
    func text(for mistake: ExerciseMistake) -> String {
        let name = mistake.control.map(controlName) ?? ""
        let step = mistake.step ?? name
        switch mistake.kind {
        case .wrongControl: return "Moviste \(name), que no forma parte de este procedimiento."
        case .undone: return "Deshiciste «\(step)»."
        case .outOfOrder: return "«\(step)» antes de terminar los pasos anteriores."
        }
    }

    /// Readable name of a control: its guide title, else its label, else its id.
    func controlName(_ id: String) -> String {
        if let title = guide.explanation(for: id)?.title { return title }
        if let label = controlsByID[id]?.label.replacingOccurrences(of: "\n", with: " "), !label.isEmpty { return label }
        return id
    }

    private func isTicked(step: ExerciseStep) -> Bool {
        manualChecks.contains("\(step.procedureID)#\(step.index)")
    }

    private func exerciseTouched(_ control: ControlDefinition) {
        guard var run = exerciseRun, run.isRunning, configurationControls.contains(control.id) else { return }
        let before = run.tracker.mistakes.count
        run.tracker.touch(control: control.id, at: exerciseElapsed())
        if run.tracker.mistakes.count != before { exerciseRun = run }
    }

    private func exerciseHint() {
        guard var run = exerciseRun, run.isRunning else { return }
        run.tracker.useHint()
        exerciseRun = run
    }

    /// Re-reads the run after the simulator or a hand tick changed something. Only writes the
    /// run back when it changed, so the panels do not redraw on every dataref update.
    private func refreshExercise() {
        guard var run = exerciseRun, run.isRunning else { return }
        let elapsed = exerciseElapsed()
        let before = (run.tracker.doneCount, run.tracker.mistakes.count, run.tracker.hints)
        run.tracker.update(at: elapsed, position: positionName(ofControl:), ticked: isTicked(step:))
        let after = (run.tracker.doneCount, run.tracker.mistakes.count, run.tracker.hints)
        if run.tracker.isComplete {
            let result = run.tracker.result(elapsed: elapsed)
            run.result = result
            exerciseResults[result.exerciseID, default: []].insert(result, at: 0)
            exerciseResults[result.exerciseID] = Array(exerciseResults[result.exerciseID, default: []].prefix(20))
        }
        guard before != after || run.result != nil else { return }
        exerciseRun = run
        // Guided: the checklist column follows the procedure of the next step.
        if run.isRunning, run.tracker.mode == .guided, let current = run.tracker.currentStep {
            let procedureID = run.tracker.steps[current].procedureID
            if activeProcedureID != procedureID { open(procedure: procedureID) }
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

    /// The camera panel is built in: it is on when layout.json declares a "camera" group.
    var hasCamera: Bool {
        layout.groups.contains { $0.id == "camera" }
    }

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
    /// In learn mode the page keys explain their page instead; data keys keep typing.
    func pressMCDU(_ key: String, duration: Double = 0) {
        if learnMode, guide.explanation(for: "mcdu.\(key)") != nil {
            explain(control: "mcdu.\(key)")
            return
        }
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
        case .procedure(let id):
            return procedure(id)?.title ?? "Procedimiento"
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
            if let baro = control.baro { names.formUnion([baro.std, baro.unit]) }
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
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await self.performConnect() }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await self.performDisconnect() }
    }

    /// Starts the demo from the connection bar, without going through the settings.
    func startDemo() {
        demoMode = true
        connect()
    }

    /// Status for the connection bar: says when the panel is running on the demo.
    var statusLabel: String {
        demoMode && status == .connected ? "Modo demo · sin simulador" : status.label
    }

    func toggleConnection() {
        if status.isActive {
            disconnect()
        } else {
            connect()
        }
    }

    private func performConnect() async {
        // A newer connect (e.g. switching demo mode, then "Iniciar demo") supersedes this one.
        connectGeneration += 1
        let generation = connectGeneration
        await performDisconnect()
        guard generation == connectGeneration else { return }
        status = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        lastError = nil

        // A fresh demo per connection: its update stream ends with the listeners that read it.
        demoSystems = nil
        demoPower = nil
        let client: any SimulatorConnection = demoMode
            ? DemoSimulator(subpanels: subpanels, fcu: fcu, systems: true, timing: demoTiming)
            : XPlaneClient(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
        self.client = client
        listen(to: client)

        do {
            try await client.connect()
            let missing = try await client.subscribe(datarefs: subscribedDatarefNames)
            guard generation == connectGeneration else { return }
            unresolved = Set(missing)
            reconnectAttempt = 0
            status = .connected
        } catch {
            guard generation == connectGeneration else { return }
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
        demoSystems = nil
        demoPower = nil
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

    private func listen(to client: any SimulatorConnection) {
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
        if update.name == DemoSystemsStatus.dataref {
            demoSystems = DemoSystemsStatus.decode(update.value)
            if demoPower != demoSystems?.power { demoPower = demoSystems?.power }
            return
        }
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
        refreshExercise()
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
        exerciseTouched(control)

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
        exerciseTouched(control)
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
        guard let lamp, let key = lamp.key, !isDemoDark else { return false }
        return lamp.isLit(lampValues[key])
    }

    /// The demo aircraft has no power at all: every annunciator is dark.
    var isDemoDark: Bool {
        guard let power = demoPower else { return false }
        return power == .none
    }

    /// Demo without the power a read-out needs: RMP 1 runs on the batteries, the other windows
    /// on AC; battery voltmeters always read.
    private func isDemoUnpowered(_ control: ControlDefinition) -> Bool {
        guard let power = demoPower else { return false }
        if (control.format ?? "").hasSuffix("V") { return false }
        let needed: DemoSystemsStatus.Power = control.id.hasPrefix("rmp1.") ? .battery : .ac
        return power < needed
    }

    /// Dual knob: one click of the outer (`small` false) or inner ring, `delta` > 0 clockwise.
    func turn(_ control: ControlDefinition, small: Bool, delta: Int) {
        guard let client, delta != 0, let commands = control.commands else { return }
        // Knobs with a single ring (BARO) turn the same way from the centre.
        let large = delta > 0 ? commands.up : commands.down
        let name = small ? ((delta > 0 ? commands.upSmall : commands.downSmall) ?? large) : large
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
        if isDemoUnpowered(control) { return "" }
        if control.format == "baro", let baro = control.baro {
            let inHg = control.state.flatMap { rawValues[$0.dataref]?.element(at: $0.index)?.doubleValue }
            return BaroBinding.text(inHg: inHg, std: rawValues[baro.std]?.doubleValue,
                                    hectopascal: rawValues[baro.unit]?.doubleValue) ?? "----"
        }
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

    // MARK: Radio tuning

    /// The parts of a radio management panel, found in its subpanel: the two text windows
    /// (ActiveWindowString / StandbyWindowString), the dual frequency knob, the transfer key
    /// and the selector keys. Any subpanel with those pieces gets the tuner.
    struct RadioPanel: Identifiable {
        let id: String
        let title: String
        let active: ControlDefinition
        let standby: ControlDefinition
        let knob: ControlDefinition
        let transfer: ControlDefinition?
        /// VHF 1, VHF 2… keys that pick the radio being tuned.
        let selectors: [ControlDefinition]
    }

    enum TuningState: Equatable {
        case idle
        case tuning(Int)
        case done(Int)
        case failed(String)
    }

    var radioPanels: [RadioPanel] {
        subpanels.compactMap { radio($0.id) }
    }

    func radio(_ panelID: String?) -> RadioPanel? {
        guard let panelID, let panel = subpanels.first(where: { $0.id == panelID }) else { return nil }
        func window(_ fragment: String) -> ControlDefinition? {
            panel.controls.first { $0.kind == .display && ($0.state?.dataref.contains(fragment) ?? false) }
        }
        guard let active = window("ActiveWindow"), let standby = window("StandbyWindow"),
              let knob = panel.controls.first(where: { $0.kind == .dualKnob }) else { return nil }
        let transfer = panel.controls.first { $0.commands?.press?.localizedCaseInsensitiveContains("swap") ?? false }
        let selectors = panel.controls.filter { $0.kind == .korry && ($0.label.hasPrefix("VHF") || $0.label.hasPrefix("HF")) }
        return RadioPanel(id: panel.id, title: displayTitle(of: panel), active: active, standby: standby,
                          knob: knob, transfer: transfer, selectors: selectors)
    }

    /// Radio whose panel holds the control, for controls that open the tuner when tapped.
    func radio(containing control: ControlDefinition) -> RadioPanel? {
        guard let panel = panelOfControl[control.id], let radio = radio(panel) else { return nil }
        return [radio.knob.id, radio.standby.id, radio.active.id].contains(control.id) ? radio : nil
    }

    /// Window text as a frequency in kHz ("121.800" → 121800), nil for courses, ADF or blank.
    static func kilohertz(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains("."), let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 1000).rounded())
    }

    static func format(kilohertz: Int) -> String {
        String(format: "%d.%03d", kilohertz / 1000, kilohertz % 1000)
    }

    func standbyKilohertz(_ radio: RadioPanel) -> Int? {
        Self.kilohertz(displayText(of: radio.standby))
    }

    func openTuner(_ radio: RadioPanel) {
        if case .tuning = tuning {} else { tuning = .idle }
        tuningRadioID = radio.id
    }

    func swap(_ radio: RadioPanel) {
        if let transfer = radio.transfer { press(transfer) }
    }

    /// One click of the outer ring (MHz) or the inner knob (kHz).
    func step(_ radio: RadioPanel, megahertz: Bool, by delta: Int) {
        turn(radio.knob, small: !megahertz, delta: delta)
    }

    /// Turns the knob until the standby window shows `target` (kHz), then transfers it to active
    /// when asked. Closed loop: whole MHz on the outer ring, then the inner knob, measuring the
    /// size of one inner click first, so it works with 25 kHz and 8.33 kHz spacing alike.
    func tune(_ radio: RadioPanel, to target: Int, transfer: Bool) {
        tuningTask?.cancel()
        tuning = .tuning(target)
        tuningTask = Task { [weak self] in
            guard let self else { return }
            let reached = await self.drive(radio, to: target)
            guard !Task.isCancelled else { return }
            guard let reached else {
                self.tuning = .failed("La ventana STBY no muestra una frecuencia. Pulsa VHF 1 o VHF 2.")
                return
            }
            if transfer, reached == target { self.swap(radio) }
            self.tuning = reached == target ? .done(target) : .failed("Quedó en \(Self.format(kilohertz: reached)): el paso del mando no llega a esa frecuencia.")
            self.remember(target)
        }
    }

    func cancelTuning() {
        tuningTask?.cancel()
        tuning = .idle
    }

    private func remember(_ frequency: Int) {
        recentFrequencies = Array(([frequency] + recentFrequencies.filter { $0 != frequency }).prefix(8))
    }

    /// Returns the standby frequency it ended on, nil when the window is not a frequency.
    private func drive(_ radio: RadioPanel, to target: Int) async -> Int? {
        guard var current = standbyKilohertz(radio) else { return nil }
        var innerStep: Int?
        for _ in 0..<6 {
            // Outer ring: whole megahertz, one click per MHz.
            let megahertz = target / 1000 - current / 1000
            if megahertz != 0 {
                current = await clicks(radio, megahertz: true, count: megahertz, from: current) ?? current
                continue
            }
            // Inner knob: learn the click size, then go most of the way in one burst.
            let difference = target % 1000 - current % 1000
            guard difference != 0 else { return current }
            guard let step = innerStep else {
                let before = current
                guard let after = await clicks(radio, megahertz: false, count: difference > 0 ? 1 : -1, from: current) else { return current }
                var moved = after % 1000 - before % 1000
                if moved > 500 { moved -= 1000 } else if moved < -500 { moved += 1000 }
                guard moved != 0 else { return after }
                innerStep = abs(moved)
                current = after
                continue
            }
            let count = Int((Double(difference) / Double(step)).rounded())
            if count == 0 { return current }
            guard let after = await clicks(radio, megahertz: false, count: count, from: current) else { return current }
            current = after
        }
        return current
    }

    /// Fires `count` clicks (sign = direction) and waits for the standby window to settle.
    private func clicks(_ radio: RadioPanel, megahertz: Bool, count: Int, from current: Int) async -> Int? {
        guard let client, let commands = radio.knob.commands, count != 0 else { return nil }
        let name = megahertz ? (count > 0 ? commands.up : commands.down)
                             : (count > 0 ? commands.upSmall : commands.downSmall)
        guard let name else { return nil }
        do {
            for _ in 0..<min(abs(count), 120) {
                try await client.fire(command: name)
            }
        } catch {
            lastError = describe(error)
            return nil
        }
        // Wait for the change, then for 0.2 s without further changes (bursts arrive in pieces).
        var last = current
        var stableSince = Date()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            guard let now = standbyKilohertz(radio) else { continue }
            if now != last {
                last = now
                stableSince = Date()
            } else if last != current, Date().timeIntervalSince(stableSince) > 0.2 {
                break
            }
        }
        return last
    }

    // MARK: Baro

    /// A BARO reference: the window (state in inHg) and the knob (push STD / pull QNH, turn),
    /// found in the same subpanel.
    struct BaroPanel: Identifiable {
        let id: String
        let title: String
        let window: ControlDefinition
        let knob: ControlDefinition?
        let unit: ControlDefinition?
    }

    var baroPanels: [BaroPanel] {
        subpanels.compactMap { baroPanel($0.id) }
    }

    func baroPanel(_ panelID: String?) -> BaroPanel? {
        guard let panelID, let panel = subpanels.first(where: { $0.id == panelID }),
              let window = panel.controls.first(where: { $0.format == "baro" && $0.baro != nil && $0.state != nil }) else { return nil }
        let knob = panel.controls.first { $0.baro != nil && $0.kind == .dualKnob }
        let unit = panel.controls.first { $0.state?.dataref == window.baro?.unit && $0.kind != .display }
        return BaroPanel(id: panel.id, title: displayTitle(of: panel), window: window, knob: knob, unit: unit)
    }

    func baroPanel(containing control: ControlDefinition) -> BaroPanel? {
        guard control.baro != nil, let panel = panelOfControl[control.id] else { return nil }
        return baroPanel(panel)
    }

    /// BARO panel whose sheet is open.
    var baroSheetPanelID: String?

    func openBaroSheet(_ panel: BaroPanel) {
        baroSheetPanelID = panel.id
    }

    func isStandard(_ panel: BaroPanel) -> Bool {
        guard let std = panel.window.baro?.std else { return false }
        return (rawValues[std]?.doubleValue ?? 0) > 0.5
    }

    func isHectopascal(_ panel: BaroPanel) -> Bool {
        guard let unit = panel.window.baro?.unit else { return true }
        return (rawValues[unit]?.doubleValue ?? 1) > 0.5
    }

    func inHg(_ panel: BaroPanel) -> Double? {
        guard let state = panel.window.state else { return nil }
        return rawValues[state.dataref]?.element(at: state.index)?.doubleValue
    }

    /// Push (STD) or pull (QNH) the knob.
    func setStandard(_ panel: BaroPanel, _ standard: Bool) {
        guard let command = standard ? panel.knob?.commands?.press : panel.knob?.commands?.pull else { return }
        fire(baroCommand: command)
    }

    func setHectopascal(_ panel: BaroPanel, _ hectopascal: Bool) {
        guard let client, let unit = panel.window.baro?.unit else { return }
        rawValues[unit] = .number(hectopascal ? 1 : 0)   // optimistic
        Task {
            do { try await client.write(DatarefKey(unit), XPValue(hectopascal ? 1.0 : 0.0)) } catch { self.lastError = self.describe(error) }
        }
    }

    /// Sets the reference directly (writing inHg) and leaves STD for QNH, as when the pilot
    /// pulls the knob and dials. Accepts hPa (800…1100) or inHg (25…33).
    @discardableResult
    func setQNH(_ panel: BaroPanel, _ value: Double) -> Bool {
        let inHg: Double
        if (800...1100).contains(value) {
            inHg = value / BaroBinding.hectopascalsPerInHg
        } else if (25...33).contains(value) {
            inHg = value
        } else {
            return false
        }
        guard let client, let state = panel.window.state else { return false }
        if isStandard(panel) { setStandard(panel, false) }
        rawValues[state.dataref] = .number(inHg)   // optimistic
        Task {
            do { try await client.write(state.key, XPValue(inHg)) } catch { self.lastError = self.describe(error) }
        }
        return true
    }

    /// Copies one side's setting and mode to every other BARO panel ("BARO REF ... SET BOTH").
    func syncBaro(from source: BaroPanel) {
        guard let value = inHg(source) else { return }
        for other in baroPanels where other.id != source.id {
            setHectopascal(other, isHectopascal(source))
            if isStandard(source) {
                if !isStandard(other) { setStandard(other, true) }
            } else {
                setQNH(other, value)
            }
        }
    }

    private func fire(baroCommand command: String) {
        guard let client else { return }
        Task {
            do { try await client.fire(command: command) } catch { self.lastError = self.describe(error) }
        }
    }

    // MARK: Cameras

    struct CameraCommand: Identifiable, Hashable, Codable {
        let name: String
        let title: String
        var id: String { name }
    }

    /// X-Camera commands found in the simulator on the last search, persisted.
    private(set) var xCameraCommands: [CameraCommand] {
        didSet {
            if let data = try? JSONEncoder().encode(xCameraCommands) {
                UserDefaults.standard.set(data, forKey: Keys.xCamera)
            }
        }
    }
    private(set) var cameraSearchState: CameraSearchState = .idle

    enum CameraSearchState: Equatable {
        case idle
        case searching
        case found(Int)
        case failed(String)
    }

    /// Lists the commands X-Camera registered in the simulator (it registers one per view, with
    /// names that depend on the user's setup) instead of guessing them.
    func searchXCameraCommands() {
        guard let client, status == .connected else {
            cameraSearchState = .failed("Conecta con X-Plane para buscar las vistas de X-Camera.")
            return
        }
        guard let xplane = client as? XPlaneClient else {
            cameraSearchState = .failed("En modo demo no hay X-Camera.")
            return
        }
        cameraSearchState = .searching
        Task {
            do {
                let found = try await xplane.searchCommands(containing: "X-Camera")
                let commands = found
                    .map { CameraCommand(name: $0.name, title: Self.cameraTitle($0.name, description: $0.description)) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.xCameraCommands = commands
                self.cameraSearchState = .found(commands.count)
            } catch {
                self.cameraSearchState = .failed(self.describe(error))
            }
        }
    }

    /// "SRS/X-Camera/Select_View_ID_3" → "Select View ID 3"; the description when it has one.
    static func cameraTitle(_ name: String, description: String?) -> String {
        if let description, !description.trimmingCharacters(in: .whitespaces).isEmpty { return description }
        let last = name.split(separator: "/").last.map(String.init) ?? name
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Fires a camera command once (view selection, quick look).
    func fireCamera(_ command: String) {
        guard let client else { return }
        Task {
            do { try await client.fire(command: command) } catch { self.lastError = self.describe(error) }
        }
    }

    /// Holds a camera movement command while the finger is down (pan, zoom, rotate).
    func holdCamera(_ command: String, active: Bool) {
        guard let client else { return }
        Task {
            do {
                if let xplane = client as? XPlaneClient {
                    try await xplane.hold(command: command, active: active)
                } else if active {
                    try await client.fire(command: command)
                }
            } catch {
                self.lastError = self.describe(error)
            }
        }
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

    /// An unpowered FCU shows no lights either.
    func isLit(_ button: FCUButtonDefinition) -> Bool {
        isFCUPowered && isOn(button.lit)
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
