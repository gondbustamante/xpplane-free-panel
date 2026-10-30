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

    func testDecodesChecksManualAndDefaults() throws {
        let json = """
        { "id": "ground", "title": "Tierra", "turnarounds": [
          { "id": "quick", "title": "Escala corta", "boardingMinutes": 15, "deboardingMinutes": 8, "milestones": [
            { "id": "deboard", "title": "Desembarque", "minutes": -33, "service": "deboarding" },
            { "id": "walk", "title": "Inspección exterior", "minutes": -25, "manual": true },
            { "id": "slides", "title": "Toboganes armados", "minutes": -3,
              "checks": [ { "control": "ground.slides", "expect": ["ARMED"] } ] }
          ] } ] }
        """
        let template = try XCTUnwrap(JSONDecoder().decode(TurnaroundBook.self, from: Data(json.utf8)).turnarounds.first)
        XCTAssertEqual(template.boardingMinutes, 15)
        XCTAssertTrue(template.uses(.deboarding))
        XCTAssertFalse(template.uses(.refuel))
        XCTAssertTrue(template.milestones[1].isManual)
        XCTAssertFalse(template.milestones[0].isManual)
        XCTAssertEqual(template.milestones[2].checks?.first?.expect, ["ARMED"])
    }

    func testOldPlanStillDecodes() throws {
        // A plan saved before slots and short turns existed.
        let plan = TurnaroundPlan(templateID: "departure", offBlocks: offBlocks)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
        json.removeValue(forKey: "taxiMinutes")
        let decoded = try JSONDecoder().decode(TurnaroundPlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.ctot)
        XCTAssertEqual(decoded.taxi, 10)
    }

    func testSlotWindow() {
        let slot = SlotWindow(ctot: at(20), taxiMinutes: 12)
        XCTAssertEqual(slot.targetOffBlocks, at(8))
        XCTAssertEqual(slot.latestOffBlocks, at(18))
        XCTAssertEqual(slot.status(now: at(0), outTime: nil), .onTime)
        XCTAssertEqual(slot.status(now: at(15), outTime: nil), .tight)
        XCTAssertEqual(slot.status(now: at(19), outTime: nil), .missed)
        XCTAssertEqual(slot.status(now: at(30), outTime: at(17)), .onTime)
    }

    func testPunctualityA15AndDelayCodes() {
        func entry(_ delay: Double?) -> FlightLogEntry {
            FlightLogEntry(flightNumber: "", origin: "", destination: "", offBlocksPlanned: offBlocks,
                           times: BlockTimes(outTime: delay.map { at($0) }), passengers: 0)
        }
        let log = [entry(3), entry(16), entry(15), entry(nil)]
        XCTAssertEqual(FlightLogEntry.a15(log)!, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(FlightLogEntry.a15([entry(nil)]))
        XCTAssertEqual(DelayCode.named(93)?.group, "Reaccionario")
        XCTAssertNil(DelayCode.named(nil))
        XCTAssertEqual(Set(DelayCode.common.map(\.code)).count, DelayCode.common.count)
    }

    func testUnknownReadingsDoNotStamp() {
        var detector = BlockTimeDetector()
        detector.update(at: at(0), parkBrake: nil, onGround: nil)
        detector.update(at: at(1), parkBrake: false, onGround: true)
        XCTAssertNil(detector.times.outTime, "the first known reading is the reference, not a change")
    }
}
