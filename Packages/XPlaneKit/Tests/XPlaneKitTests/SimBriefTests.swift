import XCTest
@testable import XPlaneKit

final class SimBriefTests: XCTestCase {
    /// Trimmed from a real SimBrief OFP: everything is text and `{}` means "nothing".
    private let json = """
    {
      "fetch": { "userid": "123", "static_id": {}, "status": "Success" },
      "params": { "request_id": "190447011", "time_generated": "1792500800", "airac": "2503", "units": "kgs" },
      "general": { "icao_airline": "VLG", "flight_number": "1234", "costindex": "30", "initial_altitude": "35000",
                   "avg_temp_dev": "1", "avg_tropopause": "36094", "avg_wind_dir": "269", "avg_wind_spd": "042",
                   "stepclimb_string": "LEMD/0350/VLC/0370", "route_distance": "297",
                   "route": "NANDO2N NANDO UN725 BLV DCT SLL UN976 VERSO VERSO1D",
                   "sid_ident": "NANDO2N", "sid_trans": {}, "star_ident": "VERSO1D", "star_trans": "VERSO" },
      "origin": { "icao_code": "LEMD", "name": "MADRID BARAJAS", "elevation": "1998", "plan_rwy": "36L",
                  "trans_alt": "13000", "trans_level": "14000" },
      "destination": { "icao_code": "LEBL", "elevation": "13", "plan_rwy": "24R", "trans_alt": "06000", "trans_level": "07000" },
      "alternate": { "icao_code": "LEGE", "name": "GIRONA", "plan_rwy": "20" },
      "atc": { "callsign": "VLG1234" },
      "aircraft": { "icaocode": "A320", "reg": "EC-MAX" },
      "fuel": { "taxi": "200", "enroute_burn": "3510", "contingency": "176", "alternate_burn": "1050", "reserve": "1060",
                "extra": "0", "plan_takeoff": "5796", "plan_ramp": "5996", "plan_landing": "2286" },
      "weights": { "pax_count": "168", "payload": "16632", "est_zfw": "59132", "max_zfw": "62500", "est_tow": "64928",
                   "max_tow": "78000", "est_ldw": "61418", "max_ldw": "66000" },
      "times": { "est_time_enroute": "3420", "sched_out": "1792502700", "taxi_out": "720" },
      "tlr": {
        "takeoff": { "conditions": { "planned_runway": "36L" },
                     "runway": [ { "identifier": "36R", "speeds_v1": "140" },
                                 { "identifier": "36L", "flap_setting": "1+F", "thrust_setting": "D-TO", "flex_temperature": "52",
                                   "speeds_v1": "143", "speeds_vr": "145", "speeds_v2": "149", "ils_frequency": "109.90" } ] },
        "landing": { "conditions": { "planned_runway": "24R", "surface_condition": "wet" },
                     "runway": [ { "identifier": "24R", "ils_frequency": "110.30", "length": "10997", "length_lda": "8530" } ] }
      }
    }
    """

    private func ofp() throws -> SimBriefOFP {
        try SimBriefOFP.parse(Data(json.utf8))
    }

    func testParsesTextValuesAndEmptyObjects() throws {
        let ofp = try ofp()
        XCTAssertEqual(ofp.callsign, "VLG1234")
        XCTAssertEqual(ofp.origin.icao, "LEMD")
        XCTAssertEqual(ofp.origin.runway, "36L")
        XCTAssertEqual(ofp.alternate?.icao, "LEGE")
        XCTAssertEqual(ofp.costIndex, 30)
        XCTAssertEqual(ofp.initialAltitude, 35000)
        XCTAssertNil(ofp.sidTransition, "{} reads as nothing")
        XCTAssertEqual(ofp.fuel.block, 5996)
        XCTAssertEqual(ofp.weights.zeroFuel, 59132)
        XCTAssertEqual(ofp.weights.passengers, 168)
        XCTAssertEqual(ofp.taxiOutMinutes, 12)
        XCTAssertEqual(ofp.takeoff?.v1, 143, "the planned runway, not the first one")
        XCTAssertEqual(ofp.takeoff?.flexTemperature, 52)
        XCTAssertEqual(ofp.landingILSFrequency, "110.30")
        XCTAssertEqual(ofp.landingRunwayLDA, 8530)
        XCTAssertEqual(LandingDistance.Surface(simBrief: ofp.landingSurface), .wet)
    }

    func testSimBriefErrorIsReported() {
        let error = Data(#"{ "fetch": { "status": "Error: Unknown UserID" } }"#.utf8)
        XCTAssertThrowsError(try SimBriefOFP.parse(error)) { error in
            XCTAssertEqual(error as? SimBriefOFP.ParseError, .simBrief("Error: Unknown UserID"))
        }
    }

    func testRouteLegsCruiseTemperatureAndSteps() throws {
        let ofp = try ofp()
        let route = ofp.routeLegs
        XCTAssertEqual(route.start, "NANDO")
        XCTAssertEqual(route.legs.map(\.via), ["UN725", "DCT", "UN976"])
        XCTAssertEqual(route.legs.map(\.to), ["BLV", "SLL", "VERSO"])
        XCTAssertEqual(ofp.cruiseTemperature, -53)   // ISA -54.3 at FL350, +1
        XCTAssertEqual(ofp.stepClimbList.map(\.fix), ["VLC"])
        XCTAssertEqual(ofp.stepClimbList.map(\.level), [370])
    }

    func testFetchURL() {
        XCTAssertEqual(SimBriefOFP.fetchURL(user: "123456")?.absoluteString,
                       "https://www.simbrief.com/api/xml.fetcher.php?userid=123456&json=1")
        XCTAssertEqual(SimBriefOFP.fetchURL(user: " gonzalo ")?.absoluteString,
                       "https://www.simbrief.com/api/xml.fetcher.php?username=gonzalo&json=1")
        XCTAssertNil(SimBriefOFP.fetchURL(user: "  "))
    }

    func testGuideValuesInMCDUFormat() throws {
        let steps = MCDUGuide.steps(for: try ofp())
        func value(_ step: String, _ entry: String) -> String? {
            steps.first { $0.id == step }?.entries.first { $0.id == entry }?.value
        }
        XCTAssertEqual(steps.first?.id, "data_airac")
        XCTAssertEqual(value("init_fromto", "fromto"), "LEMD/LEBL")
        XCTAssertEqual(value("init_ci", "ci"), "30")
        XCTAssertEqual(value("init_crz", "crz"), "350/-53")
        XCTAssertEqual(value("init_wind", "wind"), "269/042/350")
        XCTAssertEqual(value("initb_zfw", "zfw"), "59.1/")
        XCTAssertEqual(value("initb_block", "block"), "6.0")
        XCTAssertEqual(value("perf_speeds", "v2"), "149")
        XCTAssertEqual(value("perf_flaps", "flaps"), "1/")
        XCTAssertEqual(value("perf_trans", "trans"), "13000")
        XCTAssertEqual(value("radnav_ils", "ils"), "109.90")
        XCTAssertEqual(steps.first { $0.id == "fpln_route" }?.entries.count, 6)
        XCTAssertTrue(steps.first { $0.id == "fpln_arrival" }?.later ?? false)
    }

    func testWeatherATISNotamsAndFlightPlan() throws {
        let json = """
        { "origin": { "icao_code": "EDDM", "metar_category": "VFR", "taf": "EDDM 231100Z 2312/2418 31005KT CAVOK",
                      "atis": [ { "network": "vatsim", "letter": "C",
                                  "message": "MUENCHEN INFORMATION C RUNWAYS IN USE 26L AND 26R TRL 60 WIND 320 DEGREES 7 KNOTS TEMPERATURE 12 DEW POINT -2 QNH 1017" } ],
                      "notam": [ { "notam_id": "A1234/26", "notam_text": "RWY 08L/26R CLSD 2200-0500" } ] },
          "destination": { "icao_code": "EDDS", "metar_category": "lifr", "atis": {}, "notam": {} },
          "atc": { "flightplan_text": "(FPL-DLH123-IS -A320/M-SDE2E3FGHIRWY/LB1 -EDDM1515 -N0450F360 RIDA6S RIDAR -EDDS0050 EDDF)" },
          "navlog": { "fix": [ { "ident": "DM052", "pos_lat": "48.3", "pos_long": "11.5", "via_airway": "RIDA6S", "is_sid_star": "1" } ] } }
        """
        let ofp = try SimBriefOFP.parse(Data(json.utf8))
        XCTAssertEqual(ofp.origin.weatherCategory, "vfr")
        XCTAssertEqual(ofp.destination.weatherCategory, "lifr")
        XCTAssertEqual(ofp.origin.notams, ["A1234/26: RWY 08L/26R CLSD 2200-0500"])
        XCTAssertNil(ofp.destination.notams)
        let atis = ATISInfo.parse(try XCTUnwrap(ofp.origin.atis?.first))
        XCTAssertEqual(atis.letter, "C")
        XCTAssertEqual(atis.runway, "26L")
        XCTAssertEqual(atis.windSpeed, 7)
        XCTAssertEqual(atis.qnh, 1017)
        XCTAssertEqual(atis.transitionLevel, 60)
        XCTAssertTrue(ofp.atcFlightPlan?.hasPrefix("(FPL-DLH123") ?? false)
        XCTAssertEqual(ofp.fixes.first?.isProcedure, true)
        XCTAssertEqual(ofp.fixes.first?.airway, "RIDA6S")
    }

    func testExtraFuelGoesOnTheBlock() throws {
        let steps = MCDUGuide.steps(for: try ofp(), extraFuel: 500)
        XCTAssertEqual(steps.first { $0.id == "initb_block" }?.entries.first?.value, "6.5")
    }

    func testChecksAcceptEitherUnit() {
        let zfw = GuideCheck(dataref: "z", kind: .mass, expected: 59.132)
        XCTAssertEqual(zfw.matches(.number(59.1)), true)
        XCTAssertEqual(zfw.matches(.number(59132)), true)
        XCTAssertEqual(zfw.matches(.number(61.0)), false)
        XCTAssertNil(zfw.matches(.number(0)), "nothing entered yet")
        let level = GuideCheck(dataref: "c", kind: .flightLevel, expected: 350)
        XCTAssertEqual(level.matches(.number(35000)), true)
        XCTAssertEqual(level.matches(.number(350)), true)
        let flight = GuideCheck(dataref: "f", kind: .text, expectedText: "VLG1234")
        XCTAssertEqual(flight.matches(.string("vlg1234")), true)
        XCTAssertNil(flight.matches(.string("")))
    }
}
