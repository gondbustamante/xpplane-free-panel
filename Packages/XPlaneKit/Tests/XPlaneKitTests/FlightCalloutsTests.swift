import XCTest
@testable import XPlaneKit

final class FlightCalloutsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func final(_ height: Double, ias: Double = 135, vs: Double = -700, bank: Double = 0, pitch: Double = 2,
                       loc: Double? = 0, gs: Double? = 0) -> DeviationCallouts.Snapshot {
        .init(heightAboveField: height, onGround: false, ias: ias, targetSpeed: 135, verticalSpeed: vs,
              bank: bank, pitch: pitch, localizerDots: loc, glideslopeDots: gs)
    }

    /// Runs snapshots one second apart and collects the calls.
    private func run(_ callouts: inout DeviationCallouts, _ snapshots: [DeviationCallouts.Snapshot]) -> [DeviationCallouts.Callout] {
        var calls: [DeviationCallouts.Callout] = []
        for (second, snapshot) in snapshots.enumerated() {
            calls += callouts.update(snapshot, at: t0.addingTimeInterval(Double(second)))
        }
        return calls
    }

    // MARK: Deviations

    func testStableApproachCallsNothing() {
        var callouts = DeviationCallouts()
        XCTAssertEqual(run(&callouts, [final(3000), final(900), final(700), final(500), final(300), final(100), final(40)]), [])
    }

    func testDeviationNeedsToPersist() {
        var callouts = DeviationCallouts()
        // One second of 9° bank is a gust; two seconds is a call.
        XCTAssertEqual(run(&callouts, [final(3000), final(900, bank: 9), final(850), final(800, bank: 9), final(750, bank: 9),
                                       final(700, bank: 9)]), [.bank])
    }

    func testEachLimit() {
        var callouts = DeviationCallouts()
        let calls = run(&callouts, [final(3000),
                                    final(900, ias: 128, vs: -1200, bank: -8, pitch: -3, loc: 0.8, gs: -1.3),
                                    final(800, ias: 128, vs: -1200, bank: -8, pitch: -3, loc: 0.8, gs: -1.3),
                                    final(700, ias: 128, vs: -1200, bank: -8, pitch: -3, loc: 0.8, gs: -1.3)])
        XCTAssertEqual(Set(calls), Set(DeviationCallouts.Callout.allCases))
        XCTAssertEqual(calls.count, DeviationCallouts.Callout.allCases.count, "each one once")
    }

    func testCalledAgainAfterRecovering() {
        var callouts = DeviationCallouts()
        let calls = run(&callouts, [final(3000), final(900, ias: 150), final(850, ias: 150), final(800, ias: 150),
                                    final(750), final(700, ias: 150), final(650, ias: 150), final(600, ias: 150)])
        XCTAssertEqual(calls, [.speed, .speed])
    }

    func testNoCallsAfterTakeOffOrInTheFlare() {
        var callouts = DeviationCallouts()
        // Climbing out with 25° of bank below 1000 ft: never been above 1500, not an approach.
        let climb = (0..<5).map { _ in DeviationCallouts.Snapshot(heightAboveField: 600, onGround: false, ias: 160,
                                                                  verticalSpeed: 1500, bank: 25, pitch: 15) }
        XCTAssertEqual(run(&callouts, climb), [])
        // Flare: speed and rate bleed off below 50 ft without a call.
        var landing = DeviationCallouts()
        XCTAssertEqual(run(&landing, [final(3000), final(40, ias: 125, vs: -1100), final(30, ias: 124, vs: -1100),
                                      final(20, ias: 123, vs: -1100)]), [])
    }

    func testNoILSSignalIsNotADeviation() {
        var callouts = DeviationCallouts()
        XCTAssertEqual(run(&callouts, [final(3000), final(900, loc: 2.5, gs: 2.5), final(800, loc: 2.5, gs: 2.5),
                                       final(700, loc: nil, gs: nil)]), [])
    }

    // MARK: Altitudes

    private func climb(_ altitude: Double, vs: Double = 2000, selected: Double = 15_000) -> AltitudeCallouts.Snapshot {
        .init(altitude: altitude, verticalSpeed: vs, onGround: false, selectedAltitude: selected,
              transitionAltitude: 5000, transitionLevel: 7000)
    }

    func testClimbCalls() {
        var callouts = AltitudeCallouts()
        var calls: [AltitudeCallouts.Callout] = []
        for altitude in stride(from: 3000.0, through: 14_500, by: 500) {
            calls += callouts.update(climb(altitude))
        }
        XCTAssertEqual(calls, [.transitionAltitude, .tenThousand, .oneThousandToGo])
    }

    func testDescentCalls() {
        var callouts = AltitudeCallouts()
        var calls: [AltitudeCallouts.Callout] = []
        for altitude in stride(from: 12_000.0, through: 3500, by: -500) {
            calls += callouts.update(climb(altitude, vs: -1800, selected: 3000))
        }
        XCTAssertEqual(calls, [.tenThousand, .transitionLevel, .oneThousandToGo],
                       "no transition altitude call when descending through it")
    }

    func testLevellingAtFL100CallsOnce() {
        var callouts = AltitudeCallouts()
        var calls: [AltitudeCallouts.Callout] = []
        for altitude in [9800.0, 10_005, 9995, 10_010, 9990, 10_000] {
            calls += callouts.update(climb(altitude, vs: 0, selected: 10_000))
        }
        XCTAssertEqual(calls, [.tenThousand])
    }

    func testNewAltitudeCloseByIsNotACrossing() {
        var callouts = AltitudeCallouts()
        XCTAssertEqual(callouts.update(climb(8000, selected: 15_000)), [])
        // The pilot dials 8800: already within 1000 ft.
        XCTAssertEqual(callouts.update(climb(8100, selected: 8800)), [])
    }

    func testOnGroundCallsNothing() {
        var callouts = AltitudeCallouts()
        let parked = AltitudeCallouts.Snapshot(altitude: 9990, verticalSpeed: 0, onGround: true)
        XCTAssertEqual(callouts.update(parked), [])
        XCTAssertEqual(callouts.update(.init(altitude: 10_010, verticalSpeed: 0, onGround: true)), [])
    }
}
