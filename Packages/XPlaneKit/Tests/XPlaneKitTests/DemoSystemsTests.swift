import XCTest
@testable import XPlaneKit

final class DemoSystemsTests: XCTestCase {
    private let panel = """
    {
      "id": "test", "title": "TEST",
      "controls": [
        { "id": "elec.bat1", "label": "BAT 1", "kind": "korry", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/BatOHPArray", "index": 0, "values": [0, 1], "aliases": { "3": 1 } },
          "commands": { "up": "Bat1On", "down": "Bat1Off" } },
        { "id": "elec.ext_pwr", "label": "EXT PWR", "kind": "korry", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/ExtPowOHPArray", "index": 0, "values": [0, 1], "aliases": { "2": 0 } },
          "commands": { "up": "ExtOn", "down": "ExtOff" } },
        { "id": "elec.gpu", "label": "GND PWR", "kind": "korry", "positions": ["OFF", "ON"],
          "commands": { "press": "GpuToggle" } },
        { "id": "apu.master", "label": "MASTER SW", "kind": "korry", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/APUMaster" }, "commands": { "up": "MasterOn", "down": "MasterOff" } },
        { "id": "apu.start", "label": "START", "kind": "korry", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/APUStarter" }, "commands": { "up": "StartOn", "down": "StartOff" },
          "lamps": { "top": { "text": "AVAIL", "color": "green", "dataref": "AirbusFBW/APUAvail" } } },
        { "id": "air_cond.apu_bleed", "label": "APU BLEED", "kind": "korry", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/APUBleedSwitch" }, "commands": { "up": "BleedOn", "down": "BleedOff" } },
        { "id": "adirs.ir1", "label": "ADIR 1", "kind": "rotary", "positions": ["OFF", "NAV", "ATT"],
          "state": { "dataref": "AirbusFBW/ADIRUSwitchArray", "index": 0 }, "commands": { "up": "IrUp", "down": "IrDown" } },
        { "id": "adirs.on_bat", "label": "", "kind": "display", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/ADIRUOnBat" } },
        { "id": "eng.master2", "label": "MASTER 2", "kind": "toggle2", "positions": ["OFF", "ON"],
          "state": { "dataref": "AirbusFBW/ENG2MasterSwitch" }, "commands": { "up": "Eng2On", "down": "Eng2Off" } },
        { "id": "eng.mode", "label": "MODE", "kind": "rotary", "positions": ["CRANK", "NORM", "IGN/START"],
          "state": { "dataref": "AirbusFBW/ENGModeSwitch" }, "commands": { "up": "ModeUp", "down": "ModeDown" } }
      ]
    }
    """

    private func demo(_ timing: DemoTiming = .realistic) async throws -> DemoSimulator {
        let definition = try JSONDecoder().decode(SubpanelDefinition.self, from: Data(panel.utf8))
        let demo = DemoSimulator(subpanels: [definition], fcu: nil, systems: true, timing: timing)
        try await demo.connect()
        return demo
    }

    private func number(_ demo: DemoSimulator, _ name: String, _ index: Int? = nil) async -> Double? {
        await demo.value(of: DatarefKey(name, index: index))?.doubleValue
    }

    private func lines(_ demo: DemoSimulator) async -> [String] {
        await demo.systemsStatus().lines.map(\.text)
    }

    func testColdAndDarkThenBatteries() async throws {
        let demo = try await demo()
        var status = await demo.systemsStatus()
        XCTAssertEqual(status.power, DemoSystemsStatus.Power.none)
        try await demo.fire(command: "Bat1On")
        status = await demo.systemsStatus()
        XCTAssertEqual(status.power, .battery)
        XCTAssertEqual(status.lines.first?.text, "SOLO BATERÍAS")
    }

    func testAPUIgnoresEarlyStartThenSpoolsToAvail() async throws {
        let demo = try await demo()
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "MasterOn")
        let opening = await lines(demo)
        XCTAssertTrue(opening.contains("APU: ABRIENDO TOMA DE AIRE"))

        try await demo.fire(command: "StartOn")   // intake still closed: ignored
        let released = await number(demo, "AirbusFBW/APUStarter")
        XCTAssertEqual(released, 0)
        let notice = await lines(demo)
        XCTAssertTrue(notice.contains { $0.hasPrefix("APU START ignorado") })

        await demo.advance(by: 5)
        try await demo.fire(command: "StartOn")
        let starting = await number(demo, "AirbusFBW/APUStarter")
        XCTAssertEqual(starting, 1)
        await demo.advance(by: 25)
        let halfway = await number(demo, "AirbusFBW/APUAvail")
        XCTAssertEqual(halfway, 0)
        await demo.advance(by: 25)
        let avail = await number(demo, "AirbusFBW/APUAvail")
        let starter = await number(demo, "AirbusFBW/APUStarter")
        XCTAssertEqual(avail, 1)
        XCTAssertEqual(starter, 0)
        let status = await demo.systemsStatus()
        XCTAssertEqual(status.power, .ac)
        XCTAssertEqual(status.acSource, "APU GEN")
    }

    func testInstantTimingCompletesAtOnce() async throws {
        let demo = try await demo(.instant)
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "MasterOn")
        try await demo.fire(command: "StartOn")
        let avail = await number(demo, "AirbusFBW/APUAvail")
        XCTAssertEqual(avail, 1)
    }

    func testTimingChangeFinishesProcessUnderWay() async throws {
        let demo = try await demo()
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "IrUp")
        await demo.setTiming(.instant)
        let status = await lines(demo)
        XCTAssertTrue(status.contains("IRS ALINEADAS: 1 DE 3"))
    }

    func testADIRSAlignOnBattery() async throws {
        let demo = try await demo()
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "IrUp")
        let onBat = await number(demo, "AirbusFBW/ADIRUOnBat")
        XCTAssertEqual(onBat, 1)
        let aligning = await lines(demo)
        XCTAssertTrue(aligning.contains("IRS EN ALINEACIÓN · 10 MIN"))
        await demo.advance(by: 600)
        let aligned = await lines(demo)
        XCTAssertTrue(aligned.contains("IRS ALINEADAS: 1 DE 3"))
    }

    func testExternalPowerNeedsGPU() async throws {
        let demo = try await demo(.instant)
        try await demo.fire(command: "ExtOn")
        let withoutGPU = await number(demo, "AirbusFBW/ExtPowOHPArray", 0)
        XCTAssertEqual(withoutGPU, 0)
        try await demo.fire(command: "GpuToggle")
        let avail = await number(demo, "AirbusFBW/ExtPowOHPArray", 0)
        XCTAssertEqual(avail, 2)
        try await demo.fire(command: "ExtOn")
        let on = await number(demo, "AirbusFBW/ExtPowOHPArray", 0)
        XCTAssertEqual(on, 1)
        let status = await demo.systemsStatus()
        XCTAssertEqual(status.acSource, "EXT PWR")
    }

    func testEngineStartNeedsIgnitionAndBleed() async throws {
        let demo = try await demo(.instant)
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "Eng2On")
        var status = await lines(demo)
        XCTAssertTrue(status.contains("ENG 2: ENG MODE NO ESTÁ EN IGN/START"))
        try await demo.fire(command: "ModeUp")
        try await demo.fire(command: "ModeUp")
        status = await lines(demo)
        XCTAssertTrue(status.contains("ENG 2: SIN AIRE DE ARRANQUE (APU BLEED)"))
        try await demo.fire(command: "MasterOn")
        try await demo.fire(command: "StartOn")
        try await demo.fire(command: "BleedOn")
        status = await lines(demo)
        XCTAssertTrue(status.contains("ENG 2 EN MARCHA"))
        let source = await demo.systemsStatus().acSource
        XCTAssertEqual(source, "GEN 2")
    }

    func testResetAircraftReturnsToColdAndDark() async throws {
        let demo = try await demo(.instant)
        _ = try await demo.subscribe(datarefs: ["AirbusFBW/BatOHPArray", "AirbusFBW/APUAvail"])
        try await demo.fire(command: "Bat1On")
        try await demo.fire(command: "MasterOn")
        try await demo.fire(command: "StartOn")
        let avail = await number(demo, "AirbusFBW/APUAvail")
        XCTAssertEqual(avail, 1)

        let updates = await demo.resetAircraft()
        let battery = await number(demo, "AirbusFBW/BatOHPArray", 0)
        let apu = await number(demo, "AirbusFBW/APUAvail")
        XCTAssertEqual(battery, 0)
        XCTAssertEqual(apu, 0)
        XCTAssertEqual(Set(updates.map(\.name)), ["AirbusFBW/BatOHPArray", "AirbusFBW/APUAvail", DemoSystemsStatus.dataref])
        let status = await demo.systemsStatus()
        XCTAssertEqual(status.power, DemoSystemsStatus.Power.none)
    }

    func testStatusRoundTrip() {
        let status = DemoSystemsStatus(power: .battery, acSource: nil, lines: [.init("SOLO BATERÍAS", "amber")])
        XCTAssertEqual(DemoSystemsStatus.decode(status.encoded), status)
        XCTAssertEqual(DemoAircraft.time(600), "10 MIN")
        XCTAssertEqual(DemoAircraft.time(45), "45 S")
    }
}
