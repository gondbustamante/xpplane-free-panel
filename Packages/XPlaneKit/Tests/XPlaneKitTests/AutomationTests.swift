import XCTest
@testable import XPlaneKit

final class AutomationTests: XCTestCase {
    func testFiresOnceWhenTurningOffAfterLanding() {
        var detector = RunwayExitDetector()
        let roll: [(Bool, Double, Double)] = [
            (false, 140, 268), (true, 135, 270), (true, 100, 271), (true, 60, 270), (true, 30, 270),
            (true, 20, 290), (true, 18, 330), (true, 15, 360), (true, 15, 10),
        ]
        let fired = roll.map { detector.update(onGround: $0.0, groundspeed: $0.1, heading: $0.2) }
        XCTAssertEqual(fired, [false, false, false, false, false, false, true, false, false])
    }

    func testStoppingOnTheRunwayDoesNotFire() {
        var detector = RunwayExitDetector()
        for (ground, speed, heading) in [(false, 140.0, 90.0), (true, 130, 90), (true, 40, 91), (true, 0, 92), (true, 0, 92)] {
            XCTAssertFalse(detector.update(onGround: ground, groundspeed: speed, heading: heading))
        }
    }

    func testTaxiingBeforeTakeOffDoesNotFire() {
        var detector = RunwayExitDetector()
        // Connected on the ground: no landing seen, every turn of the taxi is ignored.
        for heading in stride(from: 0.0, through: 270, by: 45) {
            XCTAssertFalse(detector.update(onGround: true, groundspeed: 15, heading: heading))
        }
    }

    func testFastTurnIsStillTheRollout() {
        var detector = RunwayExitDetector()
        _ = detector.update(onGround: false, groundspeed: 140, heading: 10)
        _ = detector.update(onGround: true, groundspeed: 130, heading: 10)
        // A high-speed exit at 45 kt: not taxi speed yet.
        XCTAssertFalse(detector.update(onGround: true, groundspeed: 45, heading: 70))
        XCTAssertTrue(detector.update(onGround: true, groundspeed: 35, heading: 75))
    }

    func testHeadingDifferenceWrapsAround() {
        XCTAssertEqual(RunwayExitDetector.difference(350, 10), 20)
        XCTAssertEqual(RunwayExitDetector.difference(10, 350), 20)
        XCTAssertEqual(RunwayExitDetector.difference(90, 270), 180)
    }
}
