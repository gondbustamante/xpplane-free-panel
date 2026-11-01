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
}
