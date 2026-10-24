import XCTest
@testable import XPlaneKit

final class DemoSimulatorTests: XCTestCase {
    private let fuel = """
    {
      "id": "fuel", "title": "FUEL",
      "controls": [{
        "id": "fuel.l_pump1", "label": "1", "kind": "korry", "positions": ["OFF", "ON"],
        "state": { "dataref": "AirbusFBW/FuelOHPArray", "index": 0 },
        "commands": { "up": "PumpOn", "down": "PumpOff" },
        "lamps": {
          "top": { "text": "FAULT", "color": "amber", "dataref": "AirbusFBW/FuelAutoPumpSDArray", "index": 0, "onValue": 3 },
          "bottom": { "text": "OFF", "color": "white", "dataref": "AirbusFBW/FuelAutoPumpSDArray", "index": 0, "onValue": 0 }
        }
      }, {
        "id": "flaps.lever", "label": "FLAPS", "kind": "lever", "positions": ["FULL", "3", "2", "1", "0"],
        "state": { "dataref": "AirbusFBW/FlapLeverRatio", "values": [1, 0.75, 0.5, 0.25, 0] },
        "commands": { "up": "FlapsUp", "down": "FlapsDown" }
      }]
    }
    """

    private let rmp = """
    {
      "id": "rmp1", "title": "RMP",
      "controls": [
        { "id": "rmp1.active", "label": "ACTIVE", "kind": "display", "positions": ["", ""], "format": "text",
          "state": { "dataref": "AirbusFBW/RMP1/ActiveWindowString" } },
        { "id": "rmp1.stby", "label": "STBY", "kind": "display", "positions": ["", ""], "format": "text",
          "state": { "dataref": "AirbusFBW/RMP1/StandbyWindowString" } },
        { "id": "rmp1.xfer", "label": "XFER", "kind": "korry", "positions": ["", ""],
          "commands": { "press": "AirbusFBW/RMPSwapCapt" } },
        { "id": "rmp1.freq", "label": "", "kind": "dualKnob", "positions": ["", ""],
          "commands": { "up": "Lrg+", "down": "Lrg-", "upSmall": "Sml+", "downSmall": "Sml-" } }
      ]
    }
    """

    private let fcu = """
    {
      "id": "fcu", "title": "FCU",
      "selectors": [{
        "id": "fcu.spd", "label": "SPD", "alternateLabel": "MACH", "format": "speed", "alternateFormat": "mach",
        "value": { "dataref": "sim/cockpit/autopilot/airspeed" },
        "mode": { "dataref": "sim/cockpit/autopilot/airspeed_is_mach" },
        "managed": { "dataref": "AirbusFBW/SPDmanaged" },
        "dashed": { "dataref": "AirbusFBW/SPDdashed" },
        "range": { "min": 100, "max": 399 }, "alternateRange": { "min": 0.10, "max": 0.99 },
        "commands": { "increase": "spd_up", "decrease": "spd_down", "push": "spd_push", "pull": "spd_pull" }
      }, {
        "id": "fcu.alt", "label": "ALT", "format": "altitude",
        "value": { "dataref": "sim/cockpit/autopilot/altitude" },
        "range": { "min": 100, "max": 49000 },
        "commands": { "increase": "alt_up", "decrease": "alt_down" }
      }],
      "buttons": [
        { "id": "fcu.spd_mach", "label": "SPD", "column": "fcu.spd", "command": "spd_mach" },
        { "id": "fcu.ap1", "label": "AP1", "column": "center", "command": "ap1", "lit": { "dataref": "AirbusFBW/AP1Engage" } },
        { "id": "fcu.alt_step", "label": "ALT STEP", "column": "fcu.alt", "kind": "toggle",
          "state": { "dataref": "AirbusFBW/ALT100_1000" }, "positions": ["100", "1000"] }
      ]
    }
    """

    private func simulator() async throws -> DemoSimulator {
        let panels = try [fuel, rmp].map { try JSONDecoder().decode(SubpanelDefinition.self, from: Data($0.utf8)) }
        let definition = try JSONDecoder().decode(FCUDefinition.self, from: Data(fcu.utf8))
        let demo = DemoSimulator(subpanels: panels, fcu: definition)
        try await demo.connect()
        return demo
    }

    private func number(_ demo: DemoSimulator, _ name: String, _ index: Int? = nil) async -> Double? {
        await demo.value(of: DatarefKey(name, index: index))?.doubleValue
    }

    private func text(_ demo: DemoSimulator, _ name: String) async -> String? {
        await demo.value(of: DatarefKey(name))?.textValue
    }

    func testKorryCommandsMoveStateAndLamps() async throws {
        let demo = try await simulator()
        let offLamp = Lamp(text: "OFF", color: "white", dataref: nil, index: nil, onValue: 0, bit: nil, invert: nil)
        let faultLamp = Lamp(text: "FAULT", color: "amber", dataref: nil, index: nil, onValue: 3, bit: nil, invert: nil)

        let lamp = await demo.value(of: DatarefKey("AirbusFBW/FuelAutoPumpSDArray", index: 0))
        XCTAssertTrue(offLamp.isLit(lamp))
        XCTAssertFalse(faultLamp.isLit(lamp))

        try await demo.fire(command: "PumpOn")
        let state = await number(demo, "AirbusFBW/FuelOHPArray", 0)
        XCTAssertEqual(state, 1)
        let lampOn = await demo.value(of: DatarefKey("AirbusFBW/FuelAutoPumpSDArray", index: 0))
        XCTAssertFalse(offLamp.isLit(lampOn))
        XCTAssertFalse(faultLamp.isLit(lampOn))
    }

    func testLeverStartsAtZeroAndSteps() async throws {
        let demo = try await simulator()
        let start = await number(demo, "AirbusFBW/FlapLeverRatio")
        XCTAssertEqual(start, 0)
        try await demo.fire(command: "FlapsDown")
        let one = await number(demo, "AirbusFBW/FlapLeverRatio")
        XCTAssertEqual(one, 0.25)
        try await demo.fire(command: "FlapsUp")
        try await demo.fire(command: "FlapsUp")
        let clamped = await number(demo, "AirbusFBW/FlapLeverRatio")
        XCTAssertEqual(clamped, 0)
    }

    func testRMPTunesAndSwaps() async throws {
        let demo = try await simulator()
        try await demo.fire(command: "Lrg+")
        try await demo.fire(command: "Sml-")
        let tuned = await text(demo, "AirbusFBW/RMP1/StandbyWindowString")
        XCTAssertEqual(tuned, "122.475")
        try await demo.fire(command: "AirbusFBW/RMPSwapCapt")
        let active = await text(demo, "AirbusFBW/RMP1/ActiveWindowString")
        let standby = await text(demo, "AirbusFBW/RMP1/StandbyWindowString")
        XCTAssertEqual(active, "122.475")
        XCTAssertEqual(standby, "118.700")
    }

    func testFCUKnobsButtonsAndModes() async throws {
        let demo = try await simulator()
        try await demo.fire(command: "spd_up")
        let speed = await number(demo, "sim/cockpit/autopilot/airspeed")
        XCTAssertEqual(speed, 251)
        let dashed = await number(demo, "AirbusFBW/SPDdashed")
        XCTAssertEqual(dashed, 0)

        try await demo.fire(command: "spd_mach")
        let mach = await number(demo, "sim/cockpit/autopilot/airspeed")
        XCTAssertEqual(mach, 0.7)

        try await demo.write(DatarefKey("AirbusFBW/ALT100_1000"), .number(1))
        try await demo.fire(command: "alt_up")
        let altitude = await number(demo, "sim/cockpit/autopilot/altitude")
        XCTAssertEqual(altitude, 6000)

        try await demo.fire(command: "ap1")
        let ap1 = await number(demo, "AirbusFBW/AP1Engage")
        XCTAssertEqual(ap1, 1)
    }

    func testMCDUScratchpadAndPages() async throws {
        let demo = try await simulator()
        for key in ["KeyF", "KeyL", "Key3", "Key5", "Key0", "KeyClear"] {
            try await demo.fire(command: "AirbusFBW/MCDU1\(key)")
        }
        var raw: [String: XPValue] = [:]
        for name in MCDUScreen.datarefNames(unit: 1) {
            raw[name] = await demo.value(of: DatarefKey(name))
        }
        var screen = MCDUScreen.decode(unit: 1, values: raw)
        XCTAssertTrue(screen.text(row: 0).contains("MCDU MENU"))
        XCTAssertTrue(screen.text(row: 13).hasPrefix("FL35"))

        try await demo.fire(command: "AirbusFBW/MCDU1Init")
        try await demo.fire(command: "AirbusFBW/MCDU1LSK6L")
        for name in MCDUScreen.datarefNames(unit: 1) {
            raw[name] = await demo.value(of: DatarefKey(name))
        }
        screen = MCDUScreen.decode(unit: 1, values: raw)
        XCTAssertTrue(screen.text(row: 0).contains("INIT"))
        XCTAssertTrue(screen.text(row: 12).hasPrefix("FL35"))
        XCTAssertEqual(screen.cells[12][0].color, .cyan)
        XCTAssertTrue(screen.text(row: 13).trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testSubscribePublishesValuesAndChanges() async throws {
        let demo = try await simulator()
        let missing = try await demo.subscribe(datarefs: ["AirbusFBW/FuelOHPArray", "unknown/dataref"])
        XCTAssertEqual(missing, [])
        var iterator = demo.updates.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertEqual(Set([first?.name, second?.name]), ["AirbusFBW/FuelOHPArray", "unknown/dataref"])

        try await demo.fire(command: "PumpOn")
        let change = await iterator.next()
        XCTAssertEqual(change?.name, "AirbusFBW/FuelOHPArray")
        XCTAssertEqual(change?.value.element(at: 0)?.doubleValue, 1)
    }
}
