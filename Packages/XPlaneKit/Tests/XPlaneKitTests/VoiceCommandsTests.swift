import XCTest
@testable import XPlaneKit

final class VoiceCommandsTests: XCTestCase {
    private func action(_ text: String) -> VoiceCommand.Action? {
        VoiceCommandParser.parse(text)?.action
    }

    private func readback(_ text: String) -> String? {
        VoiceCommandParser.parse(text)?.readback
    }

    func testGear() {
        XCTAssertEqual(action("Gear up"), .gear(down: false))
        XCTAssertEqual(action("gear down."), .gear(down: true))
        XCTAssertEqual(action("tren arriba"), .gear(down: false))
        XCTAssertEqual(action("Tren abajo"), .gear(down: true))
    }

    func testFlapsInAnySpelling() {
        XCTAssertEqual(action("flaps one"), .set([.init("flaps.lever", "1")]))
        XCTAssertEqual(action("Flaps 2"), .set([.init("flaps.lever", "2")]))
        XCTAssertEqual(action("flaps three"), .set([.init("flaps.lever", "3")]))
        XCTAssertEqual(action("flaps full"), .set([.init("flaps.lever", "FULL")]))
        XCTAssertEqual(action("flaps up"), .set([.init("flaps.lever", "0")]))
        XCTAssertEqual(action("flaps cero"), .set([.init("flaps.lever", "0")]))
        XCTAssertEqual(readback("flaps 1"), "FLAPS ONE")
    }

    func testLights() {
        XCTAssertEqual(action("landing lights on"),
                       .set([.init("ext_lt.land_l", "ON"), .init("ext_lt.land_r", "ON")]))
        XCTAssertEqual(action("luces de aterrizaje recogidas"),
                       .set([.init("ext_lt.land_l", "RETRACT"), .init("ext_lt.land_r", "RETRACT")]))
        XCTAssertEqual(action("nose light take off"), .set([.init("ext_lt.nose", "T.O")]))
        XCTAssertEqual(action("taxi light on"), .set([.init("ext_lt.nose", "TAXI")]))
        XCTAssertEqual(action("strobe auto"), .set([.init("ext_lt.strobe", "AUTO")]))
        XCTAssertEqual(action("beacon off"), .set([.init("ext_lt.beacon", "OFF")]))
        XCTAssertEqual(action("seat belts on"), .set([.init("signs.seat_belts", "ON")]))
        XCTAssertEqual(action("apaga los cinturones"), .set([.init("signs.seat_belts", "OFF")]))
    }

    func testFlowsBeforeLights() {
        XCTAssertEqual(action("after landing flow"), .flow("after_landing_flow"))
        XCTAssertEqual(action("after takeoff checklist"), .flow("after_takeoff_flow"))
        XCTAssertEqual(action("después del despegue"), .flow("after_takeoff_flow"))
        XCTAssertEqual(action("line up items"), .flow("line_up_flow"))
        XCTAssertEqual(readback("after start"), "AFTER START FLOW")
        XCTAssertNil(action("climb"), "climb alone is a thrust or ATC word, not the flow")
        XCTAssertEqual(action("climb flow"), .flow("climb_flow"))
    }

    func testSystems() {
        XCTAssertEqual(action("arm spoilers"), .set([.init("speedbrake.lever", "ARM")]))
        XCTAssertEqual(action("disarm ground spoilers"), .set([.init("speedbrake.lever", "RET")]))
        XCTAssertEqual(action("autopilot one on"), .fcu("fcu.ap1"))
        XCTAssertEqual(action("autopilot two"), .fcu("fcu.ap2"))
        XCTAssertEqual(action("APU start"), .apuStart)
        XCTAssertEqual(action("APU bleed on"), .set([.init("air_cond.apu_bleed", "ON")]))
        XCTAssertEqual(action("TCAS TA RA"), .set([.init("tcas.mode", "TA/RA")]))
        XCTAssertEqual(action("engine anti ice on"),
                       .set([.init("anti_ice.eng1", "ON"), .init("anti_ice.eng2", "ON")]))
    }

    func testUnknownIsNil() {
        XCTAssertNil(action("what a nice day"))
        XCTAssertNil(action(""))
        XCTAssertNil(action("landing lights"), "no position said")
    }
}
