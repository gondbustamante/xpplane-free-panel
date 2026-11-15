import XCTest
@testable import XPlaneKit

final class FlightDebriefTests: XCTestCase {
    private func reading(_ time: TimeInterval, altitude: Double = 5000, height: Double = 5000, ias: Double = 220,
                         gs: Double = 250, vs: Double = 0, bank: Double = 0, pitch: Double = 2,
                         onGround: Bool = false, ra: Double = 2500) -> FlightEventDetector.Reading {
        .init(time: time, altitude: altitude, heightAboveField: height, ias: ias, groundspeed: gs,
              verticalSpeed: vs, bank: bank, pitch: pitch, onGround: onGround, radioAltitude: ra)
    }

    private func run(_ readings: [FlightEventDetector.Reading]) -> [FlightEvent] {
        var detector = FlightEventDetector()
        return readings.flatMap { detector.update($0) }
    }

    func testCleanFlightHasNoEvents() {
        XCTAssertEqual(run((0..<10).map { reading(Double($0)) }), [])
    }

    func testBankFlaggedOncePerOccurrence() {
        let events = run([reading(0, bank: 38), reading(1, bank: 38), reading(2, bank: 38), reading(3, bank: 38),
                          reading(4, bank: 20), reading(5, bank: 36), reading(6, bank: 36), reading(7, bank: 36)])
        XCTAssertEqual(events.map(\.kind), [.excessiveBank, .excessiveBank])
        XCTAssertEqual(events.first?.severity, .medium)
    }

    func testShortExceedanceIsIgnored() {
        XCTAssertEqual(run([reading(0, bank: 38), reading(1, bank: 38), reading(2)]), [])
    }

    func testSinkRateNearTheGround() {
        let events = run((0..<4).map { reading(Double($0), height: 600, vs: -1600, ra: 600) })
        XCTAssertEqual(events.map(\.kind), [.highSinkRateLow])
        XCTAssertEqual(events.first?.severity, .high)
    }

    func testTailStrikeRiskOnRotation() {
        let events = run((0..<3).map { reading(Double($0), height: 5, ias: 150, pitch: 11.5, ra: 5) })
        XCTAssertEqual(events.map(\.kind), [.tailStrikeRisk])
        XCTAssertEqual(events.first?.severity, .high)
    }

    func testSpeedBelowFL100() {
        let events = run((0..<3).map { reading(Double($0), altitude: 8000, height: 7500, ias: 285) })
        XCTAssertEqual(events.map(\.kind), [.speedBelowFL100])
    }

    func testLongFlare() {
        var readings = [reading(0, height: 80, vs: -700, ra: 80)]
        readings += (1...15).map { reading(Double($0), height: 20, vs: -100, ra: 20) }
        readings.append(reading(16, height: 0, vs: -100, onGround: true, ra: 0))
        XCTAssertEqual(run(readings).map(\.kind), [.longFlare])
    }

    func testRolloutIsNotFastTaxiButTaxiIs() {
        var readings = [reading(0, height: 10, ra: 10)]
        readings += (1...4).map { reading(Double($0), height: 0, ias: 50, gs: 45, onGround: true, ra: 0) }
        XCTAssertEqual(run(readings), [], "landing roll, not taxi")
        let taxi = (200...204).map { reading(Double($0), height: 0, ias: 30, gs: 42, onGround: true, ra: 0) }
        XCTAssertEqual(run(taxi).map(\.kind), [.fastTaxi])
    }

    func testLandingAndGateEvents() {
        XCTAssertNil(FlightEventDetector.landing(rate: 180, g: 1.2, at: 0))
        XCTAssertEqual(FlightEventDetector.landing(rate: 450, g: 1.4, at: 0)?.kind, .firmLanding)
        XCTAssertEqual(FlightEventDetector.landing(rate: 700, g: 1.4, at: 0)?.severity, .high)
        XCTAssertEqual(FlightEventDetector.unstable(gate: 500, failures: ["velocidad"], at: 0).severity, .high)
    }

    func testScore() {
        let events = [FlightEvent(kind: .excessiveBank, severity: .medium, time: 0, detail: ""),
                      FlightEvent(kind: .hardLanding, severity: .high, time: 0, detail: "")]
        let debrief = FlightDebrief(start: Date(), end: Date(), samples: [], events: events)
        XCTAssertEqual(debrief.score, 72)
        XCTAssertEqual(debrief.grade, "Mejorable")
    }
}
