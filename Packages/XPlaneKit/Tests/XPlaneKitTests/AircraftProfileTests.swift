import XCTest
@testable import XPlaneKit

final class AircraftProfileTests: XCTestCase {
    /// The repository's `mapping/` folder (the same one the app bundles).
    private var mappingFolder: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("mapping", isDirectory: true)
    }

    private func mergedA340() throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapping-test-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        let overlay = mappingFolder.appendingPathComponent(try XCTUnwrap(AircraftProfile.a340.mappingOverlay))
        return try MappingOverlay.merge(base: mappingFolder, overlay: overlay, into: destination)
    }

    // MARK: Profiles

    func testUnknownOrMissingIdFallsBackToA320() {
        XCTAssertEqual(AircraftProfile.named(nil), .a320)
        XCTAssertEqual(AircraftProfile.named("b737"), .a320)
        XCTAssertEqual(AircraftProfile.named("a340"), .a340)
    }

    func testDetectsTheLoadedAircraftFromItsICAOType() {
        XCTAssertEqual(AircraftProfile.detected(icao: "A346"), .a340)
        XCTAssertEqual(AircraftProfile.detected(icao: " a321\0\0"), .a320)
        XCTAssertNil(AircraftProfile.detected(icao: "B738"))
        XCTAssertNil(AircraftProfile.detected(icao: ""))
        XCTAssertNil(AircraftProfile.detected(icao: nil))
    }

    func testA320FiguresAreTheOnesTheAppAlwaysUsed() {
        XCTAssertEqual(AircraftProfile.a320.loadSheetBasis, .standard)
        XCTAssertEqual(AircraftProfile.a320.engineNumbers, [1, 2])
        XCTAssertEqual(Taxi.reducedEngineSaving(minutes: 15, aircraft: .a320), Taxi.singleEngineSaving(minutes: 15))
        XCTAssertEqual(WalkaroundPoint.route(for: .a320), WalkaroundPoint.route)
        XCTAssertEqual(AircraftProfile.a320.boardingMinutesRange, 5...40)
        XCTAssertEqual(AircraftProfile.a320.blockFuelRange, 1000...18_000)
    }

    func testA340Figures() {
        let a340 = AircraftProfile.a340
        XCTAssertEqual(a340.engineNumbers, [1, 2, 3, 4])
        XCTAssertEqual(a340.lateStartEnginesText, "1 y 4")
        XCTAssertEqual(a340.loadSheetBasis.maxTakeoffWeight, 368_000)
        XCTAssertEqual(Taxi.reducedEngineSaving(minutes: 15, aircraft: a340), 10 * 7 * 2)
        let route = WalkaroundPoint.route(for: a340)
        XCTAssertEqual(Set(route.map(\.id)).count, route.count, "ids repetidos en la inspección exterior")
        XCTAssertTrue(route.contains { $0.area == "Motor 4" })
        XCTAssertTrue(route.contains { $0.id == "center_gear" })
    }

    // MARK: Mapping overlay

    func testBaseMappingIgnoresTheOverlays() throws {
        let panels = try PanelLoader.loadAll(in: mappingFolder)
        let ids = Set(panels.flatMap { $0.controls.map(\.id) })
        XCTAssertTrue(ids.contains("eng.master2"))
        XCTAssertFalse(ids.contains("eng.master3"), "el A320 no debe cargar el overlay del A340")
        XCTAssertEqual(panels.count, Set(panels.map(\.id)).count)
    }

    func testMergedA340MappingReplacesPanelsAndKeepsTheShared() throws {
        let folder = try mergedA340()
        let panels = try PanelLoader.loadAll(in: folder)
        XCTAssertEqual(panels.count, Set(panels.map(\.id)).count, "subpaneles repetidos tras la fusión")
        let ids = Set(panels.flatMap { $0.controls.map(\.id) })
        for n in 1...4 {
            XCTAssertTrue(ids.contains("eng.master\(n)"))
            XCTAssertTrue(ids.contains("elec.gen\(n)"))
            XCTAssertTrue(ids.contains("fire.eng\(n)"))
            XCTAssertTrue(ids.contains("air_cond.eng\(n)_bleed"))
        }
        XCTAssertFalse(ids.contains("hyd.ptu"), "el A340 no tiene PTU")
        XCTAssertFalse(ids.contains("fuel.l_pump1"))
        // Shared with the A320: radios, EFIS, ADIRS…
        XCTAssertTrue(ids.contains("rmp1.power"))
        XCTAssertTrue(ids.contains("adirs.ir1"))
        XCTAssertNotNil(try FCULoader.loadFirst(in: folder.appendingPathComponent("fcu")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("aircraft").path))
    }

    func testA340ProceduresOnlyCheckControlsThatExist() throws {
        let folder = try mergedA340()
        let ids = Set(try PanelLoader.loadAll(in: folder).flatMap { $0.controls.map(\.id) })
        let procedures = try ProcedureLoader.loadAll(in: folder.appendingPathComponent("procedures"))
        XCTAssertFalse(procedures.isEmpty)
        for procedure in procedures {
            for item in procedure.items {
                for check in item.checks ?? [] {
                    XCTAssertTrue(ids.contains(check.control), "\(procedure.id): \(check.control) no existe")
                }
            }
        }
        let start = try XCTUnwrap(procedures.first { $0.id == "engine_start_flow" })
        let masters = start.items.compactMap { $0.checks?.first?.control }.filter { $0.hasPrefix("eng.master") }
        XCTAssertEqual(masters, ["eng.master4", "eng.master3", "eng.master2", "eng.master1"])
        // A340 checklists: CG/THS before start, the yellow electric pump sensed at the stand.
        let beforeStart = try XCTUnwrap(procedures.first { $0.id == "before_start_cl" })
        XCTAssertTrue(beforeStart.items.contains { $0.challenge == "T.O CG / THS" })
        let parking = try XCTUnwrap(procedures.first { $0.id == "parking_cl" })
        let yellow = try XCTUnwrap(parking.items.first { $0.challenge == "YELLOW ELEC PUMP" })
        XCTAssertEqual(yellow.checks?.map(\.control), ["hyd.elec_pump_y"])
    }

    func testOverlayRemovalMarkerDeletesTheBaseFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("overlay-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? fileManager.removeItem(at: root) }
        let base = root.appendingPathComponent("base"), overlay = root.appendingPathComponent("overlay")
        try fileManager.createDirectory(at: base.appendingPathComponent("overhead"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: base.appendingPathComponent("aircraft/x"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: overlay.appendingPathComponent("overhead"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: base.appendingPathComponent("overhead/a.json"))
        try Data("b".utf8).write(to: base.appendingPathComponent("overhead/b.json"))
        try Data("x".utf8).write(to: base.appendingPathComponent("aircraft/x/c.json"))
        try Data("A".utf8).write(to: overlay.appendingPathComponent("overhead/a.json"))
        try Data().write(to: overlay.appendingPathComponent("overhead/b.json.removed"))
        let merged = try MappingOverlay.merge(base: base, overlay: overlay, into: root.appendingPathComponent("merged"))
        XCTAssertEqual(MappingOverlay.relativeFiles(in: merged), ["overhead/a.json"])
        XCTAssertEqual(try String(contentsOf: merged.appendingPathComponent("overhead/a.json"), encoding: .utf8), "A")
    }

    // MARK: Behaviour per aircraft

    func testTailStrikeWarnsEarlierOnTheA340() {
        func events(pitch: Double, limit: Double) -> [FlightEvent.Kind] {
            var detector = FlightEventDetector(tailStrikePitch: limit)
            var kinds: [FlightEvent.Kind] = []
            for t in 0..<4 {
                let reading = FlightEventDetector.Reading(time: Double(t), altitude: 100, heightAboveField: 5, ias: 150,
                                                          groundspeed: 150, verticalSpeed: 300, bank: 0, pitch: pitch,
                                                          onGround: false, radioAltitude: 5)
                kinds += detector.update(reading).map(\.kind)
            }
            return kinds
        }
        XCTAssertFalse(events(pitch: 9.0, limit: AircraftProfile.a320.tailStrikePitch).contains(.tailStrikeRisk))
        XCTAssertTrue(events(pitch: 9.0, limit: AircraftProfile.a340.tailStrikePitch).contains(.tailStrikeRisk))
    }

    func testEngineAntiIceByVoiceCoversEveryEngine() throws {
        let twin = try XCTUnwrap(VoiceCommandParser.parse("engine anti ice on"))
        let quad = try XCTUnwrap(VoiceCommandParser.parse("engine anti ice on", engineCount: 4))
        guard case .set(let twinTargets) = twin.action, case .set(let quadTargets) = quad.action else {
            return XCTFail("se esperaban mandos")
        }
        XCTAssertEqual(twinTargets.map(\.control), ["anti_ice.eng1", "anti_ice.eng2"])
        XCTAssertEqual(quadTargets.map(\.control), ["anti_ice.eng1", "anti_ice.eng2", "anti_ice.eng3", "anti_ice.eng4"])
    }

    func testDemoStartsFourEnginesFromTheAPU() async throws {
        let folder = try mergedA340()
        let panels = try PanelLoader.loadAll(in: folder)
        let demo = DemoSimulator(subpanels: panels, fcu: nil, systems: true, timing: .instant)
        try await demo.connect()
        for command in ["toliss_airbus/eleccommands/Bat1On", "toliss_airbus/apucommands/MasterOn",
                        "toliss_airbus/apucommands/StarterOn", "toliss_airbus/apucommands/BleedOn",
                        "toliss_airbus/engcommands/EngineModeSwitchRight", "toliss_airbus/engcommands/EngineModeSwitchRight"] {
            try await demo.fire(command: command)
        }
        // X BLEED to AUTO, as the cockpit preparation leaves it: the APU feeds engines 3 and 4 across it.
        try await demo.write(DatarefKey("AirbusFBW/XBleedSwitch"), XPValue(1.0))
        for n in [4, 3, 2, 1] {
            try await demo.fire(command: "toliss_airbus/engcommands/Master\(n)On")
        }
        let lines = await demo.systemsStatus().lines.map(\.text)
        for n in 1...4 {
            XCTAssertTrue(lines.contains("ENG \(n) EN MARCHA"), "ENG \(n): \(lines)")
        }
    }
}
