import XCTest
@testable import XPlaneKit

final class TurnaroundTests: XCTestCase {
    private let offBlocks = Date(timeIntervalSince1970: 1_800_000_000)

    private func milestone(_ minutes: Int, event: String? = nil) -> TurnaroundMilestone {
        TurnaroundMilestone(id: "m\(minutes)", title: "Hito", minutes: minutes, note: nil, why: nil,
                            procedures: nil, service: nil, event: event)
    }

    private func at(_ minutes: Double) -> Date {
        offBlocks.addingTimeInterval(minutes * 60)
    }

    func testDecodesTemplate() throws {
        let json = """
        { "id": "ground", "title": "Tierra", "turnarounds": [
          { "id": "dep", "title": "Salida", "milestones": [
            { "id": "boarding", "title": "Embarque", "minutes": -35, "service": "boarding" },
            { "id": "out", "title": "OUT", "minutes": 0, "event": "out" },
            { "id": "prep", "title": "Prep", "minutes": -50, "procedures": ["cockpit_prep_flow"] }
          ] } ] }
        """
        let book = try JSONDecoder().decode(TurnaroundBook.self, from: Data(json.utf8))
        let milestones = try XCTUnwrap(book.turnarounds.first).milestones
        XCTAssertEqual(milestones[0].service, .boarding)
        XCTAssertEqual(milestones[1].event, "out")
        XCTAssertEqual(milestones[2].procedures, ["cockpit_prep_flow"])
    }

    func testMilestoneStates() {
        let boarding = milestone(-35)
        XCTAssertEqual(TurnaroundSchedule.state(of: boarding, offBlocks: offBlocks, now: at(-45), doneAt: nil), .upcoming)
        XCTAssertEqual(TurnaroundSchedule.state(of: boarding, offBlocks: offBlocks, now: at(-38), doneAt: nil), .due)
        XCTAssertEqual(TurnaroundSchedule.state(of: boarding, offBlocks: offBlocks, now: at(-34), doneAt: nil), .due)
        XCTAssertEqual(TurnaroundSchedule.state(of: boarding, offBlocks: offBlocks, now: at(-30), doneAt: nil), .late(5))
        XCTAssertEqual(TurnaroundSchedule.state(of: boarding, offBlocks: offBlocks, now: at(-10), doneAt: at(-32)), .done(3))
    }

    func testDelayIsWorstLateness() {
        let milestones = [milestone(-35), milestone(-10), milestone(0, event: "out")]
        let done = ["m-35": at(-33)]
        XCTAssertEqual(TurnaroundSchedule.delay(milestones, offBlocks: offBlocks, now: at(-4), doneAt: done), 6)
        XCTAssertEqual(TurnaroundSchedule.delay(milestones, offBlocks: offBlocks, now: at(5),
                                                doneAt: ["m-35": at(-33), "m-10": at(-9), "m0": at(4)]), 4)
    }

    func testServiceClockPausesAndResumes() {
        var clock = ServiceClock()
        XCTAssertEqual(clock.progress(at: at(0), duration: 600), 0)
        clock.start(at: at(0))
        XCTAssertEqual(clock.progress(at: at(5), duration: 600), 0.5, accuracy: 0.0001)
        clock.pause(at: at(5))
        XCTAssertEqual(clock.progress(at: at(8), duration: 600), 0.5, accuracy: 0.0001)
        clock.start(at: at(8))
        XCTAssertEqual(clock.progress(at: at(13), duration: 600), 1)
        XCTAssertEqual(ServiceClock().progress(at: at(0), duration: 0), 0)
    }

    func testLoadSheet() {
        let sheet = LoadSheet(passengers: 150, blockFuel: 6000)
        XCTAssertEqual(sheet.zeroFuelWeight, 42_500 + 150 * 97)
        XCTAssertEqual(sheet.takeoffWeight, sheet.zeroFuelWeight + 5800)
        XCTAssertTrue(sheet.withinLimits)
        XCTAssertFalse(LoadSheet(passengers: 400, blockFuel: 6000).withinLimits)
    }

    func testBlockTimesFromBrakeAndGround() {
        var detector = BlockTimeDetector()
        detector.update(at: at(-1), parkBrake: true, onGround: true)
        XCTAssertNil(detector.times.outTime)
        detector.update(at: at(1), parkBrake: false, onGround: true)
        XCTAssertEqual(detector.times.outTime, at(1))
        detector.update(at: at(8), parkBrake: true, onGround: true)   // holding short: not IN
        detector.update(at: at(9), parkBrake: false, onGround: true)
        detector.update(at: at(12), parkBrake: false, onGround: false)
        XCTAssertEqual(detector.times.offTime, at(12))
        detector.update(at: at(70), parkBrake: false, onGround: true)
        XCTAssertEqual(detector.times.onTime, at(70))
        detector.update(at: at(78), parkBrake: true, onGround: true)
        XCTAssertEqual(detector.times.inTime, at(78))
        XCTAssertEqual(detector.times.blockMinutes, 77)
        XCTAssertEqual(detector.times.flightMinutes, 58)
        XCTAssertEqual(detector.times.outTime, at(1), "OUT is not moved by a later release")
    }

    func testUnknownReadingsDoNotStamp() {
        var detector = BlockTimeDetector()
        detector.update(at: at(0), parkBrake: nil, onGround: nil)
        detector.update(at: at(1), parkBrake: false, onGround: true)
        XCTAssertNil(detector.times.outTime, "the first known reading is the reference, not a change")
    }
}
