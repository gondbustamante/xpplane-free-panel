import XCTest
@testable import XPlaneKit

final class FuelPlanTests: XCTestCase {
    private let json = """
    { "params": { "units": "kgs" }, "origin": { "icao_code": "LEMD" }, "destination": { "icao_code": "LEBL" },
      "fuel": { "taxi": "200", "enroute_burn": "3500", "contingency": "175", "alternate_burn": "1000", "reserve": "1000",
                "plan_takeoff": "5800", "plan_ramp": "6000", "plan_landing": "2300" },
      "times": { "est_time_enroute": "3600" },
      "navlog": { "fix": [
        { "ident": "TOC", "pos_lat": "40.6", "pos_long": "-3.0", "fuel_plan_onboard": "5000", "fuel_min_onboard": "4500", "time_total": "1200" },
        { "ident": "TOD", "pos_lat": "41.2", "pos_long": "1.5", "fuel_plan_onboard": "2700", "fuel_min_onboard": "2300", "time_total": "3000" },
        { "ident": "LEBL", "pos_lat": "41.3", "pos_long": "2.1", "fuel_plan_onboard": "2300", "fuel_min_onboard": "2050", "time_total": "3600" } ] } }
    """

    private func ofp() throws -> SimBriefOFP { try SimBriefOFP.parse(Data(json.utf8)) }

    func testPlanAsIs() throws {
        let plan = try XCTUnwrap(FuelPlan(ofp: try ofp()))
        XCTAssertEqual(plan.points.map(\.ident), ["TOC", "TOD", "LEBL"])
        XCTAssertEqual(plan.points.map(\.estimated), [5000, 2700, 2300])
        XCTAssertEqual(plan.estimatedLanding, 2300)
        XCTAssertEqual(plan.level, .onPlan)
        XCTAssertNil(plan.firstBelowMinimum)
        // 2300 landing - 2000 reserve + alternate = 300 spare over a 3500 trip.
        XCTAssertEqual(plan.marginToAlternate, 300.0 / 3500, accuracy: 0.0001)
        XCTAssertEqual(plan.marginToReserve, 1300.0 / 3500, accuracy: 0.0001)
    }

    func testBurningMore() throws {
        let plan = try XCTUnwrap(FuelPlan(ofp: try ofp(), burnDeviation: 0.10))
        // 3500 burnt to LEBL, 10 % more: 350 kg less at landing.
        XCTAssertEqual(plan.estimatedLanding, 1950, accuracy: 0.1)
        XCTAssertEqual(plan.level, .noAlternate)
        XCTAssertEqual(plan.firstBelowMinimum?.ident, "LEBL", "TOD keeps 2390 over its 2300 minimum")
    }

    func testExtraFuelCostsToCarry() throws {
        let plan = try XCTUnwrap(FuelPlan(ofp: try ofp(), extra: 1000))
        // 1000 kg carried for an hour: about 35 kg burnt carrying it.
        XCTAssertEqual(plan.estimatedLanding, 2300 + 965, accuracy: 0.1)
        XCTAssertGreaterThan(plan.marginToAlternate, 0.3)
    }
}
