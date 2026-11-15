import XCTest
@testable import XPlaneKit

final class FlightMonitorTests: XCTestCase {
    /// Three points due east along the equator, one degree (60 NM) apart.
    private let fixes = [
        SimBriefOFP.NavFix(ident: "AAA", type: "wpt", latitude: 0, longitude: 0, legDistance: 0, altitude: 30000,
                           plannedFuel: 5000, minimumFuel: 4500, timeTotal: 0, stage: "CRZ"),
        SimBriefOFP.NavFix(ident: "BBB", type: "wpt", latitude: 0, longitude: 1, legDistance: 60, altitude: 30000,
                           plannedFuel: 4400, minimumFuel: 3900, timeTotal: 480, stage: "CRZ"),
        SimBriefOFP.NavFix(ident: "CCC", type: "apt", latitude: 0, longitude: 2, legDistance: 60, altitude: 0,
                           plannedFuel: 3800, minimumFuel: 3300, timeTotal: 960, stage: "DES"),
    ]

    func testGeoDistance() {
        XCTAssertEqual(Geo.distance(0, 0, 0, 1), 60.04, accuracy: 0.1)
    }

    func testRouteProgressBetweenPoints() throws {
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 0.25, on: fixes))
        XCTAssertEqual(progress.lastPassed, 0)
        XCTAssertEqual(progress.next, 1)
        XCTAssertEqual(progress.distanceToNext, 45, accuracy: 0.5)
        XCTAssertEqual(progress.distanceToGo, 105, accuracy: 0.5)
        XCTAssertEqual(progress.plannedFuelNow!, 4850, accuracy: 5)   // a quarter of the way from 5000 to 4400
        let later = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 1.2, on: fixes))
        XCTAssertEqual(later.next, 2, "BBB is behind")
    }

    func testFuelStates() {
        func level(_ actual: Double) -> FuelStatus.Level {
            FuelStatus.evaluate(actual: actual, plannedNow: 4400, plannedLanding: 3800, finalReserve: 1100, alternate: 1200).level
        }
        XCTAssertEqual(level(4400), .onPlan)
        XCTAssertEqual(level(4000), .watch)          // lands with 3400
        XCTAssertEqual(level(2600), .noAlternate)    // lands with 2000 < 2300
        XCTAssertEqual(level(1500), .mayday)         // lands with 900 < 1100
        XCTAssertEqual(FuelStatus.evaluate(actual: 4200, plannedNow: 4400, plannedLanding: 3800, finalReserve: 1100, alternate: 1200).estimatedLanding, 3600)
    }

    func testDescentProfile() {
        XCTAssertEqual(DescentProfile.requiredDistance(altitude: 35000, destinationElevation: 0), 115)
        XCTAssertEqual(DescentProfile.idealAltitude(distanceToGo: 40, destinationElevation: 0), 10000)
        XCTAssertEqual(DescentProfile.deviation(altitude: 12000, distanceToGo: 40, destinationElevation: 0), 2000, "2000 ft high")
    }

    func testStabilisedGates() {
        var tracker = GateTracker()
        var snapshot = ApproachSnapshot(heightAboveField: 1200, landingConfiguration: true, gearDown: true,
                                        speed: 140, targetSpeed: 137, verticalSpeed: -750, localizerDots: 0.1, glideslopeDots: 0.2)
        XCTAssertNil(tracker.update(snapshot))
        snapshot.heightAboveField = 990
        XCTAssertEqual(tracker.update(snapshot)?.isStable, true)
        snapshot.heightAboveField = 600
        snapshot.speed = 160
        XCTAssertNil(tracker.update(snapshot))
        snapshot.heightAboveField = 495
        let gate500 = tracker.update(snapshot)
        XCTAssertEqual(gate500?.gate, 500)
        XCTAssertEqual(gate500?.failures.count, 1)
        XCTAssertNil(tracker.update(snapshot), "each gate once")
    }

    func testMinimumsCallouts() {
        var callouts = MinimumsCallouts()
        XCTAssertNil(callouts.update(height: 600, minimum: 200))
        XCTAssertEqual(callouts.update(height: 290, minimum: 200), .hundredAbove)
        XCTAssertNil(callouts.update(height: 250, minimum: 200))
        XCTAssertEqual(callouts.update(height: 199, minimum: 200), .minimum)
        XCTAssertNil(callouts.update(height: 150, minimum: 200))
    }

    func testLandingDetector() {
        var detector = LandingDetector()
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertNil(detector.update(onGround: false, verticalSpeed: -700, g: 1, speed: 140, at: start))
        XCTAssertNil(detector.update(onGround: false, verticalSpeed: -180, g: 1, speed: 135, at: start.addingTimeInterval(60)))
        XCTAssertNil(detector.update(onGround: true, verticalSpeed: 0, g: 1.3, speed: 134, at: start.addingTimeInterval(61)))
        let report = detector.update(onGround: true, verticalSpeed: 0, g: 1.1, speed: 120, at: start.addingTimeInterval(63))
        XCTAssertEqual(report?.rate, 180)
        XCTAssertEqual(report?.peakG, 1.3)
        XCTAssertEqual(report?.rating, "Buena")
        XCTAssertFalse(report?.isHard ?? true)
    }

    func testParsesNavlog() throws {
        let json = """
        { "params": { "units": "kgs" },
          "origin": { "icao_code": "LEMD", "pos_lat": "40.47", "pos_long": "-3.56" },
          "destination": { "icao_code": "LEBL", "pos_lat": "41.30", "pos_long": "2.08" },
          "navlog": { "fix": [
            { "ident": "TOC", "type": "ltlg", "pos_lat": "40.9", "pos_long": "-2.5", "distance": "60",
              "fuel_plan_onboard": "5100", "fuel_min_onboard": "4600", "altitude_feet": "35000" },
            { "ident": "LEBL", "type": "apt", "pos_lat": "41.30", "pos_long": "2.08", "distance": {} } ] },
          "enroute_altn": {} }
        """
        let ofp = try SimBriefOFP.parse(Data(json.utf8))
        XCTAssertEqual(ofp.fixes.count, 2)
        XCTAssertEqual(ofp.fixes[0].plannedFuel, 5100)
        XCTAssertNil(ofp.fixes[1].legDistance)
        XCTAssertEqual(ofp.destination.latitude, 41.30)
        XCTAssertEqual(ofp.enrouteAlternates, [])
    }

    // MARK: PM callouts

    private func ground(_ ias: Double, v1: Double = 140, vr: Double = 145,
                        spoilers: Bool = false, reversers: Bool = false) -> PilotMonitoringCallouts.Snapshot {
        .init(ias: ias, onGround: true, verticalSpeed: 0, radioAltitude: 0, v1: v1, vr: vr,
              spoilersDeployed: spoilers, reversersDeployed: reversers)
    }

    private func air(_ ias: Double, vs: Double, ra: Double) -> PilotMonitoringCallouts.Snapshot {
        .init(ias: ias, onGround: false, verticalSpeed: vs, radioAltitude: ra, v1: 140, vr: 145)
    }

    func testTakeoffCallsInOrderOnce() {
        var pm = PilotMonitoringCallouts()
        var calls: [PilotMonitoringCallouts.Callout] = []
        for snapshot in [ground(0), ground(60), ground(101), ground(120), ground(141), ground(146), ground(150),
                         air(155, vs: 800, ra: 10), air(158, vs: 1500, ra: 60), air(160, vs: 2000, ra: 400)] {
            calls += pm.update(snapshot)
        }
        XCTAssertEqual(calls, [.hundredKnots, .v1, .rotate, .positiveClimb])
    }

    func testRejectedTakeoffStopsCalls() {
        var pm = PilotMonitoringCallouts()
        var calls: [PilotMonitoringCallouts.Callout] = []
        for snapshot in [ground(0), ground(105), ground(125), ground(110), ground(141), ground(80), ground(20)] {
            calls += pm.update(snapshot)
        }
        XCTAssertEqual(calls, [.hundredKnots], "no V1 after the speed falls on the runway")
    }

    func testNoV1WithoutPerfData() {
        var pm = PilotMonitoringCallouts()
        var calls: [PilotMonitoringCallouts.Callout] = []
        for snapshot in [ground(0, v1: 0, vr: 0), ground(101, v1: 0, vr: 0), ground(150, v1: 0, vr: 0)] {
            calls += pm.update(snapshot)
        }
        XCTAssertEqual(calls, [.hundredKnots])
    }

    func testLandingRollCalls() {
        var pm = PilotMonitoringCallouts()
        var calls: [PilotMonitoringCallouts.Callout] = []
        for snapshot in [air(140, vs: -700, ra: 50), air(135, vs: -600, ra: 5), ground(130), ground(125, spoilers: true),
                         ground(110, spoilers: true, reversers: true), ground(90, spoilers: true, reversers: true),
                         ground(69, spoilers: true), ground(25)] {
            calls += pm.update(snapshot)
        }
        XCTAssertEqual(calls, [.spoilers, .reverseGreen, .seventyKnots])
    }

    func testJoiningMidFlightCallsNothingUntilTouchdown() {
        var pm = PilotMonitoringCallouts()
        XCTAssertEqual(pm.update(air(250, vs: 0, ra: 0)), [])
        XCTAssertEqual(pm.update(air(160, vs: -700, ra: 100)), [])
        XCTAssertEqual(pm.update(ground(130, spoilers: true)), [])
        XCTAssertEqual(pm.update(ground(128, spoilers: true)), [.spoilers])
    }
}
