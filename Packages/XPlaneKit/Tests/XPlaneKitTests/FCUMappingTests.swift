import XCTest
@testable import XPlaneKit

final class FCUFormatTests: XCTestCase {
    func testSpeedAndMach() {
        XCTAssertEqual(FCUFormat.speed.text(for: 250), "250")
        XCTAssertEqual(FCUFormat.speed.text(for: 99.6), "100")
        XCTAssertEqual(FCUFormat.speed.text(for: nil), "---")
        XCTAssertEqual(FCUFormat.mach.text(for: 0.78), ".78")
        XCTAssertEqual(FCUFormat.mach.text(for: 0.8), ".80")
        XCTAssertEqual(FCUFormat.mach.text(for: nil), "-.--")
    }

    func testHeadingWrapsAndPads() {
        XCTAssertEqual(FCUFormat.heading.text(for: 5), "005")
        XCTAssertEqual(FCUFormat.heading.text(for: 360), "000")
        XCTAssertEqual(FCUFormat.heading.text(for: -10), "350")
        XCTAssertEqual(FCUFormat.heading.text(for: 359.6), "000")
    }

    func testAltitude() {
        XCTAssertEqual(FCUFormat.altitude.text(for: 5000), "05000")
        XCTAssertEqual(FCUFormat.altitude.text(for: 39000), "39000")
        XCTAssertEqual(FCUFormat.altitude.text(for: nil), "-----")
    }

    func testVerticalSpeedShowsHundredsLikeTheRealUnit() {
        XCTAssertEqual(FCUFormat.verticalSpeed.text(for: 2500), "+25oo")
        XCTAssertEqual(FCUFormat.verticalSpeed.text(for: -1500), "-15oo")
        XCTAssertEqual(FCUFormat.verticalSpeed.text(for: 0), "+00oo")
        XCTAssertEqual(FCUFormat.verticalSpeed.text(for: nil), "-----")
    }

    func testFlightPathAngle() {
        XCTAssertEqual(FCUFormat.flightPathAngle.text(for: -3), "-3.0")
        XCTAssertEqual(FCUFormat.flightPathAngle.text(for: 2.54), "+2.5")
        XCTAssertEqual(FCUFormat.flightPathAngle.text(for: nil), "-.-")
    }

    func testParseAcceptsTypedVariants() {
        XCTAssertEqual(FCUFormat.mach.parse(".78"), 0.78)
        XCTAssertEqual(FCUFormat.mach.parse("0,78"), 0.78)
        XCTAssertEqual(FCUFormat.verticalSpeed.parse("+1500"), 1500)
        XCTAssertEqual(FCUFormat.flightPathAngle.parse("-.5"), -0.5)
        XCTAssertEqual(FCUFormat.altitude.parse(" 35000 "), 35000)
        XCTAssertNil(FCUFormat.speed.parse("abc"))
        XCTAssertNil(FCUFormat.speed.parse(""))
    }

    func testDefaultSteps() {
        XCTAssertEqual(FCUFormat.speed.defaultStep, 1)
        XCTAssertEqual(FCUFormat.mach.defaultStep, 0.01)
        XCTAssertEqual(FCUFormat.altitude.defaultStep, 100)
        XCTAssertEqual(FCUFormat.verticalSpeed.defaultStep, 100)
        XCTAssertEqual(FCUFormat.flightPathAngle.defaultStep, 0.1)
    }
}

final class FCUMappingTests: XCTestCase {
    private let sample = """
    {
      "id": "fcu", "title": "FCU",
      "available": {"dataref": "AirbusFBW/FCUAvail"},
      "selectors": [
        {"id": "fcu.spd", "label": "SPD", "alternateLabel": "MACH",
         "format": "speed", "alternateFormat": "mach",
         "value": {"dataref": "sim/cockpit/autopilot/airspeed"},
         "mode": {"dataref": "sim/cockpit/autopilot/airspeed_is_mach"},
         "managed": {"dataref": "AirbusFBW/SPDmanaged"},
         "range": {"min": 100, "max": 399}, "alternateRange": {"min": 0.1, "max": 0.99},
         "commands": {"increase": "sim/autopilot/airspeed_up", "decrease": "sim/autopilot/airspeed_down",
                      "push": "AirbusFBW/PushSPDSel", "pull": "AirbusFBW/PullSPDSel"},
         "verified": false},
        {"id": "fcu.alt", "label": "ALT", "format": "altitude",
         "value": {"dataref": "sim/cockpit/autopilot/altitude"},
         "write": {"dataref": "sim/cockpit2/autopilot/altitude_dial_ft"}}
      ],
      "buttons": [
        {"id": "fcu.ap1", "label": "AP1", "column": "center", "command": "toliss_airbus/ap1_push",
         "lit": {"dataref": "AirbusFBW/AP1Engage"}},
        {"id": "fcu.athr", "label": "A/THR", "column": "center", "command": "AirbusFBW/ATHRbutton",
         "lit": {"dataref": "AirbusFBW/ATHRmode"}},
        {"id": "fcu.alt_step", "label": "ALT STEP", "column": "fcu.alt", "kind": "toggle",
         "state": {"dataref": "AirbusFBW/ALT100_1000"}, "positions": ["100", "1000"]}
      ]
    }
    """

    private func decode() throws -> FCUDefinition {
        try JSONDecoder().decode(FCUDefinition.self, from: Data(sample.utf8))
    }

    func testDecodesAndCollectsDatarefs() throws {
        let fcu = try decode()
        XCTAssertEqual(fcu.selectors.count, 2)
        XCTAssertEqual(fcu.buttons.count, 3)
        XCTAssertEqual(fcu.datarefNames, [
            "AirbusFBW/FCUAvail",
            "sim/cockpit/autopilot/airspeed", "sim/cockpit/autopilot/airspeed_is_mach", "AirbusFBW/SPDmanaged",
            "sim/cockpit/autopilot/altitude", "sim/cockpit2/autopilot/altitude_dial_ft",
            "AirbusFBW/AP1Engage", "AirbusFBW/ATHRmode", "AirbusFBW/ALT100_1000",
        ])
        XCTAssertEqual(fcu.buttons(in: "center").map(\.id), ["fcu.ap1", "fcu.athr"])
        XCTAssertEqual(fcu.buttons(in: "fcu.alt").map(\.id), ["fcu.alt_step"])
    }

    func testSelectorModeSwitchesLabelFormatAndRange() throws {
        let spd = try decode().selectors[0]
        XCTAssertEqual(spd.activeLabel(modeOn: false), "SPD")
        XCTAssertEqual(spd.activeLabel(modeOn: true), "MACH")
        XCTAssertEqual(spd.activeFormat(modeOn: false), .speed)
        XCTAssertEqual(spd.activeFormat(modeOn: true), .mach)
        XCTAssertEqual(spd.activeRange(modeOn: true)?.max, 0.99)
        XCTAssertEqual(spd.activeValueBinding(modeOn: true).dataref, "sim/cockpit/autopilot/airspeed",
                       "without alternateValue the same dataref is read in both modes")
        XCTAssertFalse(spd.isVerified)
    }

    func testWriteBindingDefaultsToValue() throws {
        let fcu = try decode()
        XCTAssertEqual(fcu.selectors[0].writeBinding.dataref, "sim/cockpit/autopilot/airspeed")
        XCTAssertEqual(fcu.selectors[1].writeBinding.dataref, "sim/cockpit2/autopilot/altitude_dial_ft")
    }

    func testBindingFlags() {
        let flag = FCUBinding(dataref: "AirbusFBW/ATHRmode")
        XCTAssertTrue(flag.isOn(.number(2)), "armed or active both light the button")
        XCTAssertTrue(flag.isOn(.number(1)))
        XCTAssertFalse(flag.isOn(.number(0)))
        XCTAssertFalse(flag.isOn(nil))
        let exact = FCUBinding(dataref: "x", onValue: 2)
        XCTAssertTrue(exact.isOn(.number(2)))
        XCTAssertFalse(exact.isOn(.number(1)))
    }

    func testToggleButtonCyclesValues() throws {
        let toggle = try decode().buttons[2]
        XCTAssertEqual(toggle.resolvedKind, .toggle)
        XCTAssertEqual(toggle.position(for: .number(0)), 0)
        XCTAssertEqual(toggle.position(for: .number(1)), 1)
        XCTAssertEqual(toggle.nextValue(after: .number(0)), 1)
        XCTAssertEqual(toggle.nextValue(after: .number(1)), 0)
        XCTAssertEqual(toggle.nextValue(after: nil), 1, "unknown state is treated as the first position")
        XCTAssertEqual(try decode().buttons[0].resolvedKind, .push)
    }

    func testRangeClamps() {
        let range = FCURange(min: 100, max: 399)
        XCTAssertEqual(range.clamp(50), 100)
        XCTAssertEqual(range.clamp(500), 399)
        XCTAssertEqual(range.clamp(250), 250)
    }
}
