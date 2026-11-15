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

    // MARK: Triggers

    private let t0 = Date(timeIntervalSince1970: 0)

    private func air(_ altitude: Double) -> AutomationTriggers.Snapshot {
        .init(altitude: altitude, onGround: false, groundspeed: 300)
    }

    private func stand(brake: Bool = true, enginesOff: Bool = true, speed: Double = 0) -> AutomationTriggers.Snapshot {
        .init(altitude: 100, onGround: true, groundspeed: speed, parkingBrakeOn: brake, enginesOff: enginesOff)
    }

    private func run(_ triggers: inout AutomationTriggers, _ snapshots: [AutomationTriggers.Snapshot]) -> [AutomationTriggers.Event] {
        snapshots.enumerated().flatMap { second, snapshot in
            triggers.update(snapshot, at: t0.addingTimeInterval(Double(second) * 5))
        }
    }

    func testFL100InClimbAndDescentOnce() {
        var triggers = AutomationTriggers()
        let events = run(&triggers, [air(8000), air(9900), air(10_050), air(9_980), air(10_020), air(25_000),
                                     air(12_000), air(10_100), air(9_900), air(10_010), air(9_950), air(5000)])
        XCTAssertEqual(events, [.climbThroughFL100, .descendThroughFL100])
    }

    func testParkedAfterAFlight() {
        var triggers = AutomationTriggers()
        // Taxi in, brake on, engines still running, then shut down and held (5 s per step).
        let events = run(&triggers, [air(500), stand(enginesOff: false, speed: 12), stand(enginesOff: false),
                                     stand(), stand(), stand(), stand(), stand()])
        XCTAssertEqual(events, [.parked], "once, ten seconds after the engines are off")
    }

    func testNoParkingFlowWithoutAFlight() {
        var triggers = AutomationTriggers()
        XCTAssertEqual(run(&triggers, [stand(), stand(), stand(), stand(), stand()]), [])
    }

    func testReleasingTheBrakeRestartsTheWait() {
        var triggers = AutomationTriggers()
        let events = run(&triggers, [air(500), stand(), stand(brake: false), stand(), stand()])
        XCTAssertEqual(events, [], "only 5 s held after the brake came back on")
    }
}
