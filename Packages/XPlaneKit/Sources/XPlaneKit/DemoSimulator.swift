import Foundation

/// Offline stand-in for X-Plane: keeps in memory every dataref the mapping uses and answers
/// writes and commands roughly the way the ToLiss does, so the panel can be tried, shown or
/// developed without a simulator.
///
/// Everything is derived from the mapping, not hard-coded per control:
/// - Lever, rotary and korry commands move the control's `state` one position (`up`/`down`) or
///   cycle it (`press`). Writes to a separate `write` binding are mirrored into `state`.
/// - Annunciators on their own dataref follow the control: amber and red legends (FAULT, FIRE)
///   stay dark, a legend that names a position lights in that position, OFF lights at the first
///   position and any other legend (ON, OVRD, ALTN…) lights past it.
/// - FCU knobs step, wrap and clamp like the windows they feed; push/pull switch the managed dot
///   and dashes; pushbuttons toggle their light or the window mode (SPD/MACH, HDG-V/S/TRK-FPA).
/// - RMP knobs tune the standby frequency and the transfer key swaps it with the active one.
/// - The MCDU shows a few static pages, the keyboard writes in the scratchpad and the line keys
///   drop the scratchpad on the line.
///
/// With `systems` on, `DemoAircraft` adds what depends on what and what takes time (power,
/// APU, ADIRS alignment, engine start), steps it twice a second and publishes a summary on
/// `DemoSystemsStatus.dataref`; the aircraft then starts cold and dark.
///
/// State starts again from cold on every `DemoSimulator`: the panel creates one per connection.
public actor DemoSimulator: SimulatorConnection {
    public nonisolated let updates: AsyncStream<DatarefUpdate>
    public nonisolated let stateChanges: AsyncStream<XPlaneClient.State>

    private let updatesContinuation: AsyncStream<DatarefUpdate>.Continuation
    private let stateContinuation: AsyncStream<XPlaneClient.State>.Continuation
    private let controls: [PlacedControl]
    private let fcu: FCUDefinition?
    /// Dataref elements read by some control's `state`: lamps never overwrite them.
    private let stateKeys: Set<DatarefKey>

    private var values: [String: XPValue] = [:]
    private var subscribed: Set<String> = []
    private var connected = false
    private var seeded = false
    /// Position of controls without a state dataref (ECAM page keys, RMP selectors), so their
    /// lamps can follow the presses.
    private var virtualPositions: [String: Int] = [:]
    private var mcdu: [Int: MCDUState] = [:]
    private let simulatesSystems: Bool
    private let controlsByID: [String: ControlDefinition]
    private var aircraft = DemoAircraft()
    private var lastStatus: DemoSystemsStatus?
    private var lastPower: DemoSystemsStatus.Power?
    private var ticker: Task<Void, Never>?
    private var lastTick = Date()
    /// Datarefs the demo drives itself (doors, ground contact): lamps read them, never set them.
    static let ownedDatarefs: Set<String> = [
        "AirbusFBW/PaxDoorArray", "AirbusFBW/CargoDoorArray", "toliss/anim/pushback/nwgrab_ratio",
        onGroundDataref,
    ]
    static let onGroundDataref = "sim/flightmodel/failures/onground_any"

    /// Integral lighting the panel reads in "según el avión" mode; lit so the demo is not dark.
    static let backlightLevels: [String: XPValue] = [
        "AirbusFBW/IntegratedLightLevelOHP_Raw": .number(0.8),
        "AirbusFBW/IntegratedLightLevelMain_Raw": .number(0.8),
        "AirbusFBW/FCUIntegralBrightness": .number(0.8),
        "AirbusFBW/MCDUIntegBrightness": .array([.number(0.8), .number(0.8)]),
    ]

    struct PlacedControl: Sendable {
        let control: ControlDefinition
        let panel: String
    }

    /// `systems` turns on the systems model; `timing` scales how long its processes take.
    public init(subpanels: [SubpanelDefinition], fcu: FCUDefinition?, systems: Bool = false,
                timing: DemoTiming = .realistic) {
        let placed = subpanels.flatMap { panel in
            panel.controls.map { PlacedControl(control: $0, panel: panel.id) }
        }
        self.controls = placed
        self.fcu = fcu
        self.stateKeys = Set(placed.compactMap { $0.control.state?.key })
        self.simulatesSystems = systems
        self.controlsByID = Dictionary(placed.map { ($0.control.id, $0.control) }, uniquingKeysWith: { first, _ in first })
        var aircraft = DemoAircraft()
        aircraft.timing = timing
        self.aircraft = aircraft

        let (updates, updatesContinuation) = AsyncStream.makeStream(of: DatarefUpdate.self, bufferingPolicy: .bufferingNewest(1024))
        self.updates = updates
        self.updatesContinuation = updatesContinuation
        let (states, stateContinuation) = AsyncStream.makeStream(of: XPlaneClient.State.self, bufferingPolicy: .bufferingNewest(16))
        self.stateChanges = states
        self.stateContinuation = stateContinuation
    }

    // MARK: SimulatorConnection

    public func connect() async throws {
        if !seeded { reset() }
        connected = true
        stateContinuation.yield(.connected)
        if simulatesSystems {
            runSystems(dt: 0)
            syncLamps()
            publishStatus()
            startTicker()
        }
    }

    public func disconnect() async {
        connected = false
        ticker?.cancel()
        ticker = nil
        subscribed.removeAll()
        stateContinuation.yield(.disconnected)
    }

    /// Changes how long the systems take; a process under way finishes at the new pace.
    public func setTiming(_ timing: DemoTiming) {
        aircraft.timing = timing
        guard connected, simulatesSystems else { return }
        let before = values
        runSystems(dt: 0)
        syncLamps()
        publishChanges(since: before)
        publishStatus()
    }

    /// Puts the aircraft back to cold and dark (the state of a fresh connection) keeping the
    /// subscriptions and the timing. Returns the new value of every subscribed dataref, and the
    /// systems summary, so the panel can apply them at once; they are also published.
    @discardableResult
    public func resetAircraft() -> [DatarefUpdate] {
        let timing = aircraft.timing
        aircraft = DemoAircraft()
        aircraft.timing = timing
        lastPower = nil
        lastStatus = nil
        reset()
        for name in subscribed where values[name] == nil {
            values[name] = .number(0)
        }
        if simulatesSystems {
            runSystems(dt: 0)
            syncLamps()
        }
        lastTick = Date()
        var updates = subscribed.sorted().compactMap { name in
            values[name].map { DatarefUpdate(name: name, value: $0) }
        }
        if simulatesSystems {
            let status = aircraft.status(switches())
            lastStatus = status
            updates.append(DatarefUpdate(name: DemoSystemsStatus.dataref, value: status.encoded))
        }
        for update in updates {
            updatesContinuation.yield(update)
        }
        return updates
    }

    /// Summary of the systems, for tests.
    public func systemsStatus() -> DemoSystemsStatus {
        aircraft.status(switches())
    }

    /// Lets `seconds` pass at once, for tests.
    public func advance(by seconds: Double) {
        let before = values
        runSystems(dt: seconds)
        syncLamps()
        publishChanges(since: before)
        publishStatus()
    }

    /// Every name is known: datarefs outside the mapping start at zero, as a fresh one would.
    @discardableResult
    public func subscribe(datarefs names: [String]) async throws -> [String] {
        guard connected else { throw XPlaneError.notConnected }
        let added = names.filter { !subscribed.contains($0) }
        for name in added where values[name] == nil {
            values[name] = .number(0)
        }
        // A zero can light a lamp that was dark because its dataref did not exist yet.
        syncLamps()
        for name in added {
            subscribed.insert(name)
            updatesContinuation.yield(DatarefUpdate(name: name, value: values[name] ?? .number(0)))
        }
        return []
    }

    public func write(_ key: DatarefKey, _ value: XPValue) async throws {
        guard connected else { throw XPlaneError.notConnected }
        let before = values
        store(key, value)
        if key.name == "AirbusFBW/WriteFOB", let kilograms = value.doubleValue {
            // Refuelling: the tanks follow the requested fuel on board, split over the wings.
            values["toliss_airbus/fuelTankContent_kgs"] = .array([.number(kilograms / 2), .number(0), .number(kilograms / 2)])
        }
        mirrorWrite(to: key, value)
        runSystems(dt: 0)
        syncLamps()
        publishChanges(since: before)
        publishStatus()
    }

    public func fire(command name: String, duration: Double) async throws {
        guard connected else { throw XPlaneError.notConnected }
        let before = values
        if let match = Self.mcduKey(in: name) {
            pressMCDU(unit: match.unit, key: match.key)
        } else {
            applyControlCommand(name)
            applyFCUCommand(name)
            applyGroundCommand(name)
            runSystems(dt: 0)
            syncLamps()
        }
        publishChanges(since: before)
        publishStatus()
    }

    /// Current value of a dataref element, for tests.
    public func value(of key: DatarefKey) -> XPValue? {
        read(key)
    }

    // MARK: Store

    private func read(_ key: DatarefKey) -> XPValue? {
        values[key.name]?.element(at: key.index)
    }

    private func store(_ key: DatarefKey, _ value: XPValue) {
        guard let index = key.index else {
            values[key.name] = value
            return
        }
        var array = values[key.name]?.arrayValue ?? []
        if array.count <= index {
            array += Array(repeating: XPValue.number(0), count: index + 1 - array.count)
        }
        array[index] = value
        values[key.name] = .array(array)
    }

    private func publishChanges(since before: [String: XPValue]) {
        for name in subscribed {
            guard let value = values[name], value != before[name] else { continue }
            updatesContinuation.yield(DatarefUpdate(name: name, value: value))
        }
    }

    /// Text datarefs travel base64-encoded, as the Web API sends them.
    static func encodedText(_ text: String) -> XPValue {
        .string(Data(text.utf8).base64EncodedString())
    }

    // MARK: Initial state

    /// A parked aircraft: switches at the position whose raw value is 0 (or the first one), knobs
    /// half way, batteries at 28 V, FCU managed. With the systems model the batteries are off, so
    /// it starts cold and dark, and the generators are latched ON.
    private func reset() {
        values = Self.backlightLevels
        values[Self.onGroundDataref] = .number(1)
        values["AirbusFBW/PaxDoorArray"] = .array(Array(repeating: .number(0), count: 4))
        values["AirbusFBW/CargoDoorArray"] = .array(Array(repeating: .number(0), count: 2))
        virtualPositions = [:]
        for placed in controls {
            seed(placed.control)
        }
        if let fcu { seed(fcu) }
        if simulatesSystems {
            // Generators are latched ON in a parked aircraft; they wait for their engine.
            for id in ["elec.gen1", "elec.gen2", "elec.apu_gen"] {
                if let control = controlsByID[id] { setPosition(control, 1) }
            }
        }
        for unit in [1, 2] {
            mcdu[unit] = MCDUState()
            renderMCDU(unit: unit)
        }
        syncLamps()
        seeded = true
    }

    private func seed(_ control: ControlDefinition) {
        guard let state = control.state else { return }
        switch control.kind {
        case .knob:
            let range = control.range ?? ValueRange(min: 0, max: 1)
            store(state.key, .number(range.value(at: 0.5)))
        case .display:
            if control.format == "text" {
                store(state.key, Self.encodedText(Self.initialText(for: state.dataref)))
            } else {
                store(state.key, .number((control.format ?? "").hasSuffix("V") ? 28.0 : 0))
            }
        default:
            let count = max(control.positions.count, 1)
            let position = state.values?.firstIndex(of: 0) ?? 0
            store(state.key, .number(state.value(for: position, count: count)))
        }
    }

    static func initialText(for dataref: String) -> String {
        if dataref.contains("ActiveWindow") { return "118.700" }
        if dataref.contains("StandbyWindow") { return "121.500" }
        if dataref.contains("XPDR") { return "2000" }
        return ""
    }

    private func seed(_ fcu: FCUDefinition) {
        if let available = fcu.available { store(available.key, Self.flag(available, on: true)) }
        for selector in fcu.selectors {
            let initial: Double
            switch selector.format {
            case .speed: initial = 250
            case .mach: initial = 0.78
            case .heading: initial = 360
            case .altitude: initial = 5000
            case .verticalSpeed, .flightPathAngle: initial = 0
            }
            store(selector.value.key, .number(initial))
            if let mode = selector.mode { store(mode.key, Self.flag(mode, on: false)) }
            if let managed = selector.managed { store(managed.key, Self.flag(managed, on: true)) }
            if let dashed = selector.dashed { store(dashed.key, Self.flag(dashed, on: true)) }
        }
        for button in fcu.buttons {
            if let lit = button.lit { store(lit.key, Self.flag(lit, on: false)) }
            if let state = button.state { store(state.key, .number(button.values?.first ?? 0)) }
        }
    }

    // MARK: Panel controls

    private func position(of control: ControlDefinition) -> Int {
        guard let state = control.state else { return virtualPositions[control.id] ?? 0 }
        guard let raw = read(state.key) else { return 0 }
        return state.position(for: raw, count: max(control.positions.count, 1)) ?? 0
    }

    private func setPosition(_ control: ControlDefinition, _ position: Int) {
        guard let state = control.state else {
            virtualPositions[control.id] = position
            return
        }
        store(state.key, .number(state.value(for: position, count: max(control.positions.count, 1))))
    }

    private func applyControlCommand(_ name: String) {
        // Two buttons can share a command and a state (GND PWR on the overhead and GPU on the
        // ground panel): the command moves that state once, not once per button.
        var moved = Set<DatarefKey>()
        for placed in controls {
            let control = placed.control
            guard let commands = control.commands else { continue }
            if let key = control.state?.key, [commands.press, commands.up, commands.down].contains(name) {
                guard moved.insert(key).inserted else { continue }
            }
            if control.kind == .dualKnob {
                if name == commands.up { tuneStandby(in: placed.panel, megahertz: 1) }
                if name == commands.down { tuneStandby(in: placed.panel, megahertz: -1) }
                if name == commands.upSmall { tuneStandby(in: placed.panel, kilohertz: 25) }
                if name == commands.downSmall { tuneStandby(in: placed.panel, kilohertz: -25) }
                continue
            }
            let last = max(control.positions.count, 2) - 1
            if name == commands.press {
                if name.localizedCaseInsensitiveContains("swap") {
                    swapFrequencies(in: placed.panel)
                } else {
                    let current = position(of: control)
                    setPosition(control, current >= last ? 0 : current + 1)
                }
            } else if name == commands.up {
                setPosition(control, min(position(of: control) + 1, last))
            } else if name == commands.down {
                setPosition(control, max(position(of: control) - 1, 0))
            }
        }
    }

    /// A control written through `write` reads its position from `state`: follow the write.
    private func mirrorWrite(to key: DatarefKey, _ value: XPValue) {
        for placed in controls {
            let control = placed.control
            guard let write = control.write, write.key == key, let state = control.state, state.key != key else { continue }
            let count = max(control.positions.count, 1)
            guard let position = write.position(for: value, count: count) else { continue }
            store(state.key, .number(state.value(for: position, count: count)))
        }
    }

    // MARK: Lamps

    private func syncLamps() {
        var wanted: [DatarefKey: [(lamp: Lamp, lit: Bool)]] = [:]
        for placed in controls {
            let control = placed.control
            guard let lamps = control.lamps else { continue }
            let current = position(of: control)
            for lamp in [lamps.top, lamps.bottom].compactMap({ $0 }) {
                // A lamp on the control's own state dataref already follows it.
                guard let key = lamp.key, !stateKeys.contains(key), !Self.ownedDatarefs.contains(key.name) else { continue }
                let lit = systemsLamp(control.id, lamp.text) ?? Self.shouldLight(lamp, control: control, position: current)
                wanted[key, default: []].append((lamp, lit))
            }
        }
        for (key, constraints) in wanted {
            func satisfies(_ value: XPValue?) -> Bool {
                constraints.allSatisfy { $0.lamp.isLit(value) == $0.lit }
            }
            if satisfies(read(key)) { continue }
            let bits = constraints.reduce(0) { sum, item in
                guard let bit = item.lamp.bit, item.lit != (item.lamp.invert ?? false) else { return sum }
                return sum | bit
            }
            let candidates = [0, 1, 2, 3, 4, 5, Double(bits)] + constraints.compactMap { $0.lamp.onValue }
            if let raw = candidates.first(where: { satisfies(.number($0)) }) {
                store(key, .number(raw))
            }
        }
    }

    static func shouldLight(_ lamp: Lamp, control: ControlDefinition, position: Int) -> Bool {
        let text = lamp.text.uppercased()
        if let index = control.positions.firstIndex(where: { $0.uppercased() == text }) {
            return index == position
        }
        if lamp.color == "amber" || lamp.color == "red" { return false }
        if text == "OFF" { return position == 0 }
        return position > 0
    }

    // MARK: Ground services

    private var doorsOpen: Bool {
        (values["AirbusFBW/PaxDoorArray"]?.arrayValue ?? []).contains { ($0.doubleValue ?? 0) > 0.05 }
    }

    /// ISCS ground commands: doors open and close at once, slides arm only with every door
    /// closed, fast alignment finishes the IRS.
    private func applyGroundCommand(_ name: String) {
        if name.hasSuffix("door_commands/all_to_mode_open") {
            values["AirbusFBW/PaxDoorArray"] = .array(Array(repeating: .number(1), count: 4))
            values["AirbusFBW/CargoDoorArray"] = .array(Array(repeating: .number(1), count: 2))
            if let slides = controlsByID["ground.slides"] { setPosition(slides, 0) }
        } else if name.hasSuffix("door_commands/all_to_mode_close") {
            values["AirbusFBW/PaxDoorArray"] = .array(Array(repeating: .number(0), count: 4))
            values["AirbusFBW/CargoDoorArray"] = .array(Array(repeating: .number(0), count: 2))
        } else if name.hasSuffix("door_commands/arm_slides"), doorsOpen,
                  let slides = controlsByID["ground.slides"] {
            setPosition(slides, 0)
            aircraft.notify("Toboganes no armados: cierra antes todas las puertas")
        } else if name == "AirbusFBW/ADIRU_fast_align" {
            aircraft.alignNow()
        }
    }

    // MARK: Systems

    private func positionName(_ id: String) -> String? {
        guard let control = controlsByID[id] else { return nil }
        let index = position(of: control)
        return control.positions.indices.contains(index) ? control.positions[index] : nil
    }

    /// Switch positions by meaning. A missing control reads as latched in a parked aircraft:
    /// generators, bleeds, pumps and packs ON, the rest OFF.
    private func switches() -> DemoSwitches {
        func on(_ id: String, default value: Bool = false) -> Bool {
            positionName(id).map { $0 == "ON" } ?? value
        }
        var s = DemoSwitches()
        s.battery = on("elec.bat1") || on("elec.bat2")
        s.gpu = on("elec.gpu")
        s.extPower = on("elec.ext_pwr")
        s.apuMaster = on("apu.master")
        s.apuStart = on("apu.start")
        s.apuBleed = on("air_cond.apu_bleed")
        s.apuGen = on("elec.apu_gen", default: true)
        s.generators = [on("elec.gen1", default: true), on("elec.gen2", default: true)]
        s.irModes = ["adirs.ir1", "adirs.ir2", "adirs.ir3"].map { positionName($0) ?? "OFF" }
        s.engineMasters = [on("eng.master1"), on("eng.master2")]
        s.engineMode = positionName("eng.mode") ?? "NORM"
        s.engineBleeds = [on("air_cond.eng1_bleed", default: true), on("air_cond.eng2_bleed", default: true)]
        s.crossBleed = positionName("air_cond.x_bleed") ?? "AUTO"
        s.enginePumps = [on("hyd.eng1_pump", default: true), on("hyd.eng2_pump", default: true)]
        s.packs = [on("air_cond.pack1", default: true), on("air_cond.pack2", default: true)]
        s.fireHandles = ["fire.eng1", "fire.eng2"].map { positionName($0) == "PUSHED" }
        return s
    }

    /// Steps the systems and writes back what they decide: the APU START light, EXT PWR AVAIL,
    /// GEN FAULT, ON BAT, battery voltage, FCU power, the integral lighting and the MCDU.
    private func runSystems(dt: Double) {
        guard simulatesSystems else { return }
        var s = switches()
        aircraft.step(dt, s)
        if let start = controlsByID["apu.start"] {
            setPosition(start, aircraft.apuStarterLit ? 1 : 0)
        }
        s = switches()
        let power = aircraft.power(s)
        // EXT PWR: 0 without a GPU (the button does nothing), 2 AVAIL, 1 ON.
        if let ext = controlsByID["elec.ext_pwr"]?.state {
            store(ext.key, .number(s.gpu ? (s.extPower ? 1 : 2) : 0))
        }
        // GEN 1/2: ON with FAULT (3) while their engine is stopped.
        for (i, id) in ["elec.gen1", "elec.gen2"].enumerated() {
            guard let state = controlsByID[id]?.state else { continue }
            store(state.key, .number(s.generators[i] ? (aircraft.isRunning(i) ? 1 : 3) : 0))
        }
        if let onBat = controlsByID["adirs.on_bat"]?.state {
            store(onBat.key, .number(aircraft.onBattery(s) ? 1 : 0))
        }
        for placed in controls where placed.control.kind == .display && (placed.control.format ?? "").hasSuffix("V") {
            if let state = placed.control.state {
                store(state.key, .number(power == .ac ? 28.0 : 25.8))
            }
        }
        if let available = fcu?.available {
            store(available.key, Self.flag(available, on: power == .ac))
        }
        for (name, level) in Self.backlightLevels {
            let dark = level.arrayValue.map { XPValue.array($0.map { _ in XPValue.number(0) }) } ?? XPValue.number(0)
            values[name] = power == .ac ? level : dark
        }
        if power != lastPower {
            lastPower = power
            for unit in [1, 2] { renderMCDU(unit: unit) }
        }
    }

    /// Lamps the systems decide: APU AVAIL, engine pump pressure, pack without air.
    private func systemsLamp(_ id: String, _ text: String) -> Bool? {
        guard simulatesSystems else { return nil }
        switch (id, text) {
        case ("apu.start", "AVAIL"):
            return aircraft.apuAvailable
        case ("hyd.eng1_pump", "FAULT"), ("hyd.eng2_pump", "FAULT"):
            let engine = id == "hyd.eng1_pump" ? 0 : 1
            return switches().enginePumps[engine] && !aircraft.isRunning(engine)
        case ("air_cond.pack1", "FAULT"), ("air_cond.pack2", "FAULT"):
            let s = switches()
            let pack = id == "air_cond.pack1" ? 0 : 1
            return s.packs[pack] && !aircraft.bleedAvailable(s)
        default:
            return nil
        }
    }

    private func publishStatus() {
        guard simulatesSystems else { return }
        let status = aircraft.status(switches())
        guard status != lastStatus else { return }
        lastStatus = status
        updatesContinuation.yield(DatarefUpdate(name: DemoSystemsStatus.dataref, value: status.encoded))
    }

    private func startTicker() {
        ticker?.cancel()
        lastTick = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.tick()
            }
        }
    }

    private func tick() {
        guard connected else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        advance(by: dt)
    }

    // MARK: RMP

    private func textDisplay(in panel: String, matching fragment: String) -> ValueBinding? {
        controls.first {
            $0.panel == panel && $0.control.kind == .display && $0.control.format == "text"
                && ($0.control.state?.dataref.contains(fragment) ?? false)
        }?.control.state
    }

    /// Steps the standby frequency: whole megahertz between 118 and 136 on the outer ring,
    /// 25 kHz within the megahertz on the inner knob, both wrapping as on the real RMP.
    private func tuneStandby(in panel: String, megahertz: Int = 0, kilohertz: Int = 0) {
        guard let standby = textDisplay(in: panel, matching: "Standby") else { return }
        let text = read(standby.key)?.textValue ?? ""
        let current = Int(((Double(text) ?? 121.5) * 1000).rounded())
        var mhz = current / 1000
        var khz = current % 1000
        if megahertz != 0 {
            mhz = 118 + ((mhz - 118 + megahertz) % 19 + 19) % 19
        }
        if kilohertz != 0 {
            khz = ((khz + kilohertz) % 1000 + 1000) % 1000
        }
        store(standby.key, Self.encodedText(String(format: "%d.%03d", mhz, khz)))
    }

    private func swapFrequencies(in panel: String) {
        guard let active = textDisplay(in: panel, matching: "Active"),
              let standby = textDisplay(in: panel, matching: "Standby"),
              let activeValue = read(active.key), let standbyValue = read(standby.key) else { return }
        store(active.key, standbyValue)
        store(standby.key, activeValue)
    }

    // MARK: FCU

    static func flag(_ binding: FCUBinding, on: Bool) -> XPValue {
        if let onValue = binding.onValue {
            return .number(on ? onValue : (onValue == 0 ? 1 : 0))
        }
        return .number(on ? 1 : 0)
    }

    private func isOn(_ binding: FCUBinding?) -> Bool {
        guard let binding else { return false }
        return binding.isOn(read(binding.key))
    }

    private func applyFCUCommand(_ name: String) {
        guard let fcu else { return }
        for selector in fcu.selectors {
            guard let commands = selector.commands else { continue }
            if name == commands.increase { turn(selector, by: 1) }
            if name == commands.decrease { turn(selector, by: -1) }
            if name == commands.push || name == commands.pull {
                let managed = name == commands.push
                if let binding = selector.managed { store(binding.key, Self.flag(binding, on: managed)) }
                if let binding = selector.dashed { store(binding.key, Self.flag(binding, on: managed)) }
            }
        }
        for button in fcu.buttons where button.resolvedKind == .push && button.command == name {
            if let lit = button.lit {
                store(lit.key, Self.flag(lit, on: !isOn(lit)))
            } else if let selector = fcu.selectors.first(where: { $0.id == button.column }), let mode = selector.mode {
                toggleMode(mode, in: fcu)
            }
        }
    }

    private func turn(_ selector: FCUSelectorDefinition, by sign: Int) {
        let modeOn = isOn(selector.mode)
        let format = selector.activeFormat(modeOn: modeOn)
        let binding = selector.activeValueBinding(modeOn: modeOn)
        let step = altitudeStep(for: selector) ?? format.defaultStep
        let current = read(binding.key)?.doubleValue ?? 0
        var target = ((current + Double(sign) * step) / step).rounded() * step
        if format.isAngle {
            target = target.truncatingRemainder(dividingBy: 360)
            if target <= 0 { target += 360 }
        }
        if let range = selector.activeRange(modeOn: modeOn) { target = range.clamp(target) }
        store(binding.key, .number(target))
        // Turning a dashed window shows the selected value.
        if let dashed = selector.dashed { store(dashed.key, Self.flag(dashed, on: false)) }
    }

    /// ALT knob: 100 or 1000 ft, from the step selector drawn in the same column.
    private func altitudeStep(for selector: FCUSelectorDefinition) -> Double? {
        guard selector.format == .altitude,
              let button = fcu?.buttons.first(where: { $0.column == selector.id && $0.resolvedKind == .toggle }),
              let state = button.state, let positions = button.positions,
              let index = button.position(for: read(state.key)), positions.indices.contains(index) else { return nil }
        return Double(positions[index])
    }

    /// SPD/MACH and HDG-V/S/TRK-FPA: flips the flag and converts every window that shares it.
    private func toggleMode(_ mode: FCUBinding, in fcu: FCUDefinition) {
        let wasOn = isOn(mode)
        store(mode.key, Self.flag(mode, on: !wasOn))
        for selector in fcu.selectors where selector.mode?.key == mode.key && selector.alternateValue == nil {
            let from = selector.activeFormat(modeOn: wasOn)
            let to = selector.activeFormat(modeOn: !wasOn)
            guard from != to, let current = read(selector.value.key)?.doubleValue else { continue }
            var converted = Self.convert(current, from: from, to: to)
            if let range = selector.activeRange(modeOn: !wasOn) { converted = range.clamp(converted) }
            store(selector.value.key, .number(converted))
        }
    }

    /// Rough conversions so the window stays plausible: M.78 ≈ 280 kt, 1° ≈ 435 ft/min.
    static func convert(_ value: Double, from: FCUFormat, to: FCUFormat) -> Double {
        switch (from, to) {
        case (.speed, .mach): return (value * 0.78 / 280 * 100).rounded() / 100
        case (.mach, .speed): return (value * 280 / 0.78).rounded()
        case (.verticalSpeed, .flightPathAngle): return (value / 435 * 10).rounded() / 10
        case (.flightPathAngle, .verticalSpeed): return (value * 435 / 100).rounded() * 100
        default: return value
        }
    }

    // MARK: MCDU

    struct MCDUState: Sendable {
        var page = "Menu"
        var scratchpad = ""
        var message: String?
        /// What the user dropped on a line, keyed by page and line key, e.g. "Init1L".
        var entries: [String: String] = [:]
    }

    struct MCDUField: Sendable {
        var label = ""
        var text = ""
        /// Colour letter of the dataref family: "w", "b" (cyan), "g", "a"…
        var color = "w"
    }

    struct MCDUPage: Sendable {
        var title: String
        var left: [Int: MCDUField] = [:]
        var right: [Int: MCDUField] = [:]
    }

    /// "AirbusFBW/MCDU1KeyA" → (1, "KeyA").
    static func mcduKey(in command: String) -> (unit: Int, key: String)? {
        let prefix = "AirbusFBW/MCDU"
        guard command.hasPrefix(prefix) else { return nil }
        let rest = command.dropFirst(prefix.count)
        guard let first = rest.first, let unit = Int(String(first)), unit == 1 || unit == 2 else { return nil }
        let key = String(rest.dropFirst())
        return key.isEmpty ? nil : (unit, key)
    }

    static func page(_ id: String) -> MCDUPage {
        switch id {
        case "Init":
            return MCDUPage(title: "INIT", left: [
                1: MCDUField(label: "CO RTE", text: "##########", color: "a"),
                2: MCDUField(label: "ALTN/CO RTE", text: "----/----------"),
                3: MCDUField(label: "FLT NBR", text: "########", color: "a"),
                5: MCDUField(label: "COST INDEX", text: "---"),
                6: MCDUField(label: "CRZ FL/TEMP", text: "-----/---"),
            ], right: [
                1: MCDUField(label: "FROM/TO", text: "####/####", color: "a"),
                3: MCDUField(text: "IRS INIT>"),
                4: MCDUField(text: "WIND>"),
                6: MCDUField(label: "TROPO", text: "36090", color: "b"),
            ])
        case "Perf":
            return MCDUPage(title: "TAKE OFF", left: [
                1: MCDUField(label: "V1", text: "---", color: "a"),
                2: MCDUField(label: "VR", text: "---", color: "a"),
                3: MCDUField(label: "V2", text: "---", color: "a"),
                4: MCDUField(label: "TRANS ALT", text: "5000", color: "b"),
                5: MCDUField(label: "THR RED/ACC", text: "1500/1500", color: "b"),
            ], right: [
                1: MCDUField(label: "RWY", text: "--"),
                3: MCDUField(label: "FLAPS/THS", text: "[]/[    ]", color: "b"),
                4: MCDUField(label: "FLEX TO TEMP", text: "[ ]", color: "b"),
                6: MCDUField(label: "NEXT", text: "PHASE>"),
            ])
        case "Data":
            return MCDUPage(title: "DATA INDEX", left: [
                1: MCDUField(text: "<POSITION MONITOR"),
                2: MCDUField(text: "<IRS MONITOR"),
                3: MCDUField(text: "<GPS MONITOR"),
                4: MCDUField(text: "<A/C STATUS"),
            ], right: [
                5: MCDUField(label: "PILOTS", text: "ROUTES>"),
                6: MCDUField(label: "ACTIVE F-PLN", text: "WINDS>"),
            ])
        case "Fpln":
            return MCDUPage(title: "F-PLN", left: [
                1: MCDUField(text: "---F-PLN DISCONTINUITY--"),
                2: MCDUField(text: "------END OF F-PLN------"),
                6: MCDUField(label: "DEST", text: "----"),
            ], right: [
                6: MCDUField(label: "TIME  DIST  EFOB", text: "----  ----  ----"),
            ])
        case "Menu":
            return MCDUPage(title: "MCDU MENU", left: [
                1: MCDUField(text: "<FMGC", color: "g"),
                2: MCDUField(text: "<ATSU"),
                3: MCDUField(text: "<AIDS"),
                4: MCDUField(text: "<CFDS"),
            ], right: [
                6: MCDUField(label: "SIN SIMULADOR", text: "MODO DEMO", color: "b"),
            ])
        default:
            let titles = ["DirTo": "DIR TO", "Prog": "PROG", "RadNav": "RADIO NAV", "FuelPred": "FUEL PRED",
                          "SecFpln": "SEC INDEX", "ATC": "ATC MENU", "Airport": "AIRPORT"]
            return MCDUPage(title: titles[id] ?? id.uppercased(), left: [
                3: MCDUField(text: "  PAGINA NO SIMULADA"),
                4: MCDUField(text: "     EN MODO DEMO", color: "b"),
            ])
        }
    }

    private func pressMCDU(unit: Int, key: String) {
        var state = mcdu[unit] ?? MCDUState()
        state.message = nil
        if key.hasPrefix("LSK") {
            let slot = String(key.dropFirst(3))   // "1L"
            if state.scratchpad.isEmpty {
                state.message = "NOT ALLOWED"
            } else {
                state.entries[state.page + slot] = state.scratchpad
                state.scratchpad = ""
            }
        } else if key.hasPrefix("Key") {
            switch String(key.dropFirst(3)) {
            case "Clear":
                if !state.scratchpad.isEmpty { state.scratchpad.removeLast() }
            case "Space": state.scratchpad += " "
            case "Slash": state.scratchpad += "/"
            case "Decimal": state.scratchpad += "."
            case "PM":
                let last = state.scratchpad.last
                if last == "-" || last == "+" {
                    state.scratchpad.removeLast()
                    state.scratchpad += last == "-" ? "+" : "-"
                } else {
                    state.scratchpad += "-"
                }
            case let character where character.count == 1:
                state.scratchpad += character
            default:
                break   // BRT, DIM, OVFY
            }
            state.scratchpad = String(state.scratchpad.prefix(MCDUScreen.columns - 2))
        } else if !key.hasPrefix("Slew") {
            state.page = key
        }
        mcdu[unit] = state
        renderMCDU(unit: unit)
    }

    private func renderMCDU(unit: Int) {
        let prefix = MCDUScreen.prefix(unit: unit)
        guard !simulatesSystems || aircraft.power(switches()) == .ac else {
            // Without AC the MCDU is dark.
            for name in MCDUScreen.datarefNames(unit: unit) {
                values[name] = Self.encodedText("")
            }
            return
        }
        let state = mcdu[unit] ?? MCDUState()
        let page = Self.page(state.page)
        let blank = Array(repeating: Character(" "), count: MCDUScreen.columns)
        var rows: [String: [Character]] = [:]

        func put(_ suffix: String, _ text: String, right: Bool) {
            var row = rows[suffix] ?? blank
            let characters = Array(text.prefix(MCDUScreen.columns))
            let start = right ? MCDUScreen.columns - characters.count : 0
            for (offset, character) in characters.enumerated() {
                row[start + offset] = character
            }
            rows[suffix] = row
        }

        let titleStart = max((MCDUScreen.columns - page.title.count) / 2, 0)
        put("titlew", String(repeating: " ", count: titleStart) + page.title, right: false)
        for line in 1...6 {
            for (right, field) in [(false, page.left[line]), (true, page.right[line])] {
                guard let field else { continue }
                let entered = state.entries[state.page + "\(line)\(right ? "R" : "L")"]
                if !field.label.isEmpty { put("label\(line)w", field.label, right: right) }
                let text = entered ?? field.text
                if !text.isEmpty { put("cont\(line)\(entered == nil ? field.color : "b")", text, right: right) }
            }
        }

        for name in MCDUScreen.datarefNames(unit: unit) {
            values[name] = Self.encodedText("")
        }
        values[prefix + "VertSlewKeys"] = .number(0)
        for (suffix, row) in rows {
            values[prefix + suffix] = Self.encodedText(String(row))
        }
        values[prefix + "spw"] = Self.encodedText(state.message == nil ? state.scratchpad : "")
        values[prefix + "spa"] = Self.encodedText(state.message ?? "")
    }
}
