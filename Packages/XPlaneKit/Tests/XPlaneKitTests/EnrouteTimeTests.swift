import XCTest
@testable import XPlaneKit

final class EnrouteTimeTests: XCTestCase {
    /// Three points 60 NM apart along the equator, 8 minutes between each.
    private let fixes = [
        SimBriefOFP.NavFix(ident: "AAA", type: "wpt", latitude: 0, longitude: 0, legDistance: 0, altitude: 30000,
                           plannedFuel: nil, minimumFuel: nil, timeTotal: 0, stage: "CRZ"),
        SimBriefOFP.NavFix(ident: "BBB", type: "wpt", latitude: 0, longitude: 1, legDistance: 60, altitude: 30000,
                           plannedFuel: nil, minimumFuel: nil, timeTotal: 480, stage: "CRZ"),
        SimBriefOFP.NavFix(ident: "CCC", type: "apt", latitude: 0, longitude: 2, legDistance: 60, altitude: 0,
                           plannedFuel: nil, minimumFuel: nil, timeTotal: 960, stage: "DES"),
    ]
    private let now = Date(timeIntervalSince1970: 10_000)

    func testPlannedTimeIsInterpolatedAlongTheLeg() throws {
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 0.25, on: fixes))
        XCTAssertEqual(try XCTUnwrap(EnrouteTime.plannedElapsed(at: progress, on: fixes)), 120, accuracy: 3,
                       "a quarter of the 8-minute leg")
    }

    func testLateAgainstThePlanAndTheSchedule() throws {
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 1.5, on: fixes))
        // Took off 15 minutes ago; the plan has us here at 12.
        let time = try XCTUnwrap(EnrouteTime.evaluate(
            now: now, takeOff: now.addingTimeInterval(-900), progress: progress, fixes: fixes, totalPlanned: 960,
            scheduledIn: now.addingTimeInterval(600), taxiIn: 5))
        XCTAssertEqual(time.plannedElapsed, 720, accuracy: 5)
        XCTAssertEqual(time.deviation!, 180, accuracy: 5, "three minutes late")
        XCTAssertEqual(time.remaining, 240, accuracy: 5)
        XCTAssertEqual(time.landing.timeIntervalSince(now), 240, accuracy: 5)
        XCTAssertEqual(time.arrivalDelay!, 240 + 300 - 600, accuracy: 5, "a minute early on blocks")
    }

    func testWithoutTakeOffOrScheduleThereIsNoDeviation() throws {
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 0.5, on: fixes))
        let time = try XCTUnwrap(EnrouteTime.evaluate(now: now, takeOff: nil, progress: progress, fixes: fixes,
                                                      totalPlanned: 960, scheduledIn: nil, taxiIn: 0))
        XCTAssertNil(time.deviation)
        XCTAssertNil(time.arrivalDelay)
    }

    func testSpeedToMakeUpTime() throws {
        // 5 minutes late with 450 NM of cruise at 450 kt (1 h): 55 minutes needed → about 491 kt.
        let advice = try XCTUnwrap(SpeedAdvice.toRecover(late: 300, cruiseDistance: 450, groundspeed: 450, tasPerMach: 580))
        XCTAssertEqual(advice.groundspeedChange, 450 / (55.0 / 60) - 450, accuracy: 0.5)
        XCTAssertEqual(advice.machChange!, advice.groundspeedChange / 580, accuracy: 0.0001)
        XCTAssertFalse(advice.feasible, "41 kt is more than the cost index can give")
        let small = try XCTUnwrap(SpeedAdvice.toRecover(late: 150, cruiseDistance: 900, groundspeed: 450, tasPerMach: 580))
        XCTAssertTrue(small.feasible)
        let early = try XCTUnwrap(SpeedAdvice.toRecover(late: -180, cruiseDistance: 900, groundspeed: 450, tasPerMach: nil))
        XCTAssertLessThan(early.groundspeedChange, 0, "early: slow down")
        XCTAssertNil(SpeedAdvice.toRecover(late: 60, cruiseDistance: 900, groundspeed: 450, tasPerMach: nil), "on time")
        XCTAssertNil(SpeedAdvice.toRecover(late: 600, cruiseDistance: 10, groundspeed: 450, tasPerMach: nil), "no cruise left")
    }

    func testHoldingTime() {
        // 1150 kg above reserve and alternate at 2300 kg/h: 30 minutes.
        XCTAssertEqual(HoldingTime.available(estimatedLandingFuel: 4_350, finalReserve: 1_100, alternate: 2_100), 30)
        XCTAssertEqual(HoldingTime.available(estimatedLandingFuel: 3_000, finalReserve: 1_100, alternate: 2_100), 0)
    }
}
