import XCTest
@testable import XPlaneKit

final class CabinCrewTests: XCTestCase {
    private typealias S = CabinTimeline.Snapshot

    private func ground(_ gs: Double = 0, beacon: Bool = false, strobe: Bool = false) -> S {
        S(onGround: true, groundspeed: gs, altitude: 100, verticalSpeed: 0, beaconOn: beacon, strobeOn: strobe, seatBeltsOn: true)
    }

    private func air(_ altitude: Double, vs: Double, belts: Bool = true) -> S {
        S(onGround: false, groundspeed: 400, altitude: altitude, verticalSpeed: vs, beaconOn: true, strobeOn: true, seatBeltsOn: belts)
    }

    /// One snapshot every `step` seconds.
    private func run(_ timeline: inout CabinTimeline, _ snapshots: [S], step: TimeInterval = 10) -> [CabinTimeline.Moment] {
        snapshots.enumerated().flatMap { index, snapshot in
            timeline.update(snapshot, at: Date(timeIntervalSince1970: Double(index) * step))
        }
    }

    func testWholeFlightInOrder() {
        var timeline = CabinTimeline()
        var flight: [S] = [ground(), ground(beacon: true), ground(5.5, beacon: true)]
        flight += Array(repeating: ground(15, beacon: true), count: 6)          // 60 s of taxi
        flight += [ground(10, beacon: true, strobe: true), air(2000, vs: 2500), air(9000, vs: 2500),
                   air(12_000, vs: 2000, belts: false)]
        flight += Array(repeating: air(36_000, vs: 0, belts: false), count: 14)  // 140 s level
        flight += [air(33_000, vs: -2000), air(20_000, vs: -2000), air(9_000, vs: -1500), air(2_000, vs: -800),
                   ground(120, beacon: true, strobe: true), ground(20, beacon: true), ground(0, beacon: false)]
        XCTAssertEqual(run(&timeline, flight), [.welcome, .cabinSecureTakeoff, .seatsForTakeoff, .beltsOff, .cruise,
                                                .descent, .cabinSecureLanding, .arrival, .disembark])
    }

    func testStrobeBeforeTheDelayStillReportsSecureFirst() {
        var timeline = CabinTimeline()
        let moments = run(&timeline, [ground(), ground(beacon: true), ground(8, beacon: true),
                                      ground(8, beacon: true, strobe: true)], step: 5)
        XCTAssertEqual(moments, [.welcome, .cabinSecureTakeoff, .seatsForTakeoff])
    }

    func testJoinedInCruiseSkipsTheDeparture() {
        var timeline = CabinTimeline()
        let moments = run(&timeline, [air(35_000, vs: 0, belts: false), air(30_000, vs: -2000), air(8_000, vs: -1500)])
        XCTAssertEqual(moments, [.descent, .cabinSecureLanding])
    }

    func testShortFlightBelowFL200() {
        var timeline = CabinTimeline()
        let moments = run(&timeline, [ground(), ground(beacon: true), ground(10, beacon: true),
                                      ground(10, beacon: true, strobe: true), air(6000, vs: 2000), air(14_000, vs: 0),
                                      air(11_000, vs: -1500), air(9_000, vs: -1500)])
        XCTAssertEqual(moments, [.welcome, .cabinSecureTakeoff, .seatsForTakeoff, .descent, .cabinSecureLanding])
    }

    func testMETARTemperature() {
        XCTAssertEqual(CabinTimeline.temperature(metar: "LEMD 151030Z 02008KT CAVOK 18/04 Q1021 NOSIG"), 18)
        XCTAssertEqual(CabinTimeline.temperature(metar: "EGLL 151020Z 24012KT 9999 FEW020 M02/M05 Q1008"), -2)
        XCTAssertEqual(CabinTimeline.temperature(metar: "LEBL 151030Z 02008KT 9999 21/ Q1015"), 21)
        XCTAssertNil(CabinTimeline.temperature(metar: "LEMD 151030Z 02008KT 1200 R18/0600 Q1021"))
    }
}
