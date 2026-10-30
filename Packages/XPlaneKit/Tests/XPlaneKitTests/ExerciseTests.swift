import XCTest
@testable import XPlaneKit

final class ExerciseTests: XCTestCase {
    private let json = """
    {
      "id": "normal", "title": "Normal",
      "procedures": [
        { "id": "power", "kind": "flow", "title": "Encendido",
          "items": [
            { "challenge": "BAT", "response": "ON", "checks": [ { "control": "bat", "expect": ["ON"] } ] },
            { "challenge": "EXT PWR", "response": "ON", "optional": true, "checks": [ { "control": "ext", "expect": ["ON"] } ] },
            { "challenge": "FIRE TEST", "response": "PERFORM" },
            { "challenge": "MODE", "response": "IGN", "checks": [ { "control": "mode", "expect": ["IGN"] } ] },
            { "challenge": "APU", "response": "ON", "checks": [ { "control": "apu", "expect": ["ON"] } ] }
          ] },
        { "id": "start", "kind": "flow", "title": "Arranque",
          "items": [
            { "challenge": "BAT", "response": "ON", "checks": [ { "control": "bat", "expect": ["ON"] } ] },
            { "challenge": "MODE", "response": "NORM", "checks": [ { "control": "mode", "expect": ["NORM"] } ] }
          ] }
      ]
    }
    """

    private let definition = ExerciseDefinition(id: "ex", title: "Ejercicio", summary: nil, level: nil,
                                                procedures: ["power", "start"], targetSeconds: 100, start: nil)

    private func procedures() throws -> [Procedure] {
        try JSONDecoder().decode(ProcedureBook.self, from: Data(json.utf8)).procedures
    }

    private func tracker(_ mode: ExerciseMode = .guided, settle: Double = 0) throws -> ExerciseTracker {
        ExerciseTracker(definition: definition, procedures: try procedures(), mode: mode, settle: settle)
    }

    func testStepsSkipOptionalAndRepeatedChecks() throws {
        let guided = try tracker()
        XCTAssertEqual(guided.steps.map(\.item.challenge), ["BAT", "FIRE TEST", "MODE", "APU", "MODE"])
        let exam = try tracker(.exam)
        XCTAssertEqual(exam.steps.map(\.item.challenge), ["BAT", "MODE", "APU", "MODE"])
    }

    func testCleanRunCompletesWithoutMistakes() throws {
        var run = try tracker(.exam)
        var state = ["bat": "OFF", "mode": "NORM", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        XCTAssertEqual(run.doneAtStart, [3])   // MODE NORM already in place
        state["bat"] = "ON"
        run.update(at: 5, position: { state[$0] }, ticked: { _ in false })
        state["mode"] = "IGN"
        run.update(at: 8, position: { state[$0] }, ticked: { _ in false })
        state["apu"] = "ON"
        run.update(at: 10, position: { state[$0] }, ticked: { _ in false })
        state["mode"] = "NORM"
        run.update(at: 12, position: { state[$0] }, ticked: { _ in false })
        XCTAssertTrue(run.isComplete)
        XCTAssertTrue(run.mistakes.isEmpty, "\(run.mistakes)")
        XCTAssertEqual(run.result(elapsed: 12).score, 100)
    }

    func testOutOfOrderUndoneAndWrongControl() throws {
        var run = try tracker(.exam)
        var state = ["bat": "OFF", "mode": "NORM", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        state["apu"] = "ON"   // before BAT and MODE IGN
        run.update(at: 1, position: { state[$0] }, ticked: { _ in false })
        state["apu"] = "OFF"  // undone
        run.update(at: 2, position: { state[$0] }, ticked: { _ in false })
        run.touch(control: "wing", at: 3)
        run.touch(control: "bat", at: 3)   // part of the exercise: not a mistake
        XCTAssertEqual(run.mistakes.map(\.kind), [.outOfOrder, .undone, .wrongControl])
        XCTAssertEqual(run.result(elapsed: 3).score, 100 - 3 - 5 - 2)
    }

    func testForcedTickCountsAsHint() throws {
        var run = try tracker(.guided)
        let state = ["bat": "OFF", "mode": "NORM", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        run.update(at: 1, position: { state[$0] }, ticked: { $0.item.challenge == "BAT" || $0.item.challenge == "FIRE TEST" })
        XCTAssertEqual(run.hints, 1)
        XCTAssertEqual(run.doneCount, 3)   // BAT, FIRE TEST and MODE NORM
    }

    func testIntermediatePositionIsNotJudged() throws {
        // ENG MODE goes CRANK → NORM → IGN/START: passing NORM must not tick the later
        // "MODE NORM" step out of order.
        var run = try tracker(.exam, settle: 2)
        var state = ["bat": "ON", "mode": "CRANK", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        XCTAssertEqual(run.doneAtStart, [0])
        state["mode"] = "NORM"
        run.update(at: 1.0, position: { state[$0] }, ticked: { _ in false })
        state["mode"] = "IGN"
        run.update(at: 1.6, position: { state[$0] }, ticked: { _ in false })
        run.update(at: 4, position: { state[$0] }, ticked: { _ in false })
        XCTAssertTrue(run.mistakes.isEmpty, "\(run.mistakes)")
        XCTAssertTrue(run.isDone(1))
        XCTAssertFalse(run.isDone(3), "NORM was only passed through")
    }

    func testPositionHeldIsJudgedAfterSettling() throws {
        var run = try tracker(.exam, settle: 2)
        var state = ["bat": "OFF", "mode": "NORM", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        state["apu"] = "ON"   // before BAT: out of order once it holds
        run.update(at: 1, position: { state[$0] }, ticked: { _ in false })
        XCTAssertTrue(run.mistakes.isEmpty, "not judged while it may still be on its way")
        run.update(at: 3.5, position: { state[$0] }, ticked: { _ in false })
        XCTAssertEqual(run.mistakes.map(\.kind), [.outOfOrder])
        XCTAssertEqual(run.mistakes.first?.at, 1, "stamped when the position was reached")
    }

    func testBriefUndoIsForgiven() throws {
        var run = try tracker(.exam, settle: 2)
        var state = ["bat": "ON", "mode": "NORM", "apu": "OFF"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        state["bat"] = "OFF"
        run.update(at: 1, position: { state[$0] }, ticked: { _ in false })
        state["bat"] = "ON"
        run.update(at: 1.5, position: { state[$0] }, ticked: { _ in false })
        run.update(at: 5, position: { state[$0] }, ticked: { _ in false })
        XCTAssertTrue(run.mistakes.isEmpty, "\(run.mistakes)")
        XCTAssertTrue(run.isDone(0))
    }

    func testFinishedAtIsWhenTheLastStepWasReached() throws {
        var run = try tracker(.exam, settle: 2)
        var state = ["bat": "ON", "mode": "IGN", "apu": "ON"]
        run.update(at: 0, position: { state[$0] }, ticked: { _ in false })
        state["mode"] = "NORM"
        run.update(at: 10, position: { state[$0] }, ticked: { _ in false })
        XCTAssertNil(run.finishedAt)
        run.update(at: 13, position: { state[$0] }, ticked: { _ in false })
        XCTAssertTrue(run.isComplete)
        XCTAssertEqual(run.finishedAt, 10)
    }

    func testStartingState() {
        let plain = ExerciseDefinition(id: "a", title: "A", procedures: [], targetSeconds: 10)
        XCTAssertFalse(plain.hasStartingState)
        let setup = ExerciseDefinition(id: "b", title: "B", procedures: [], targetSeconds: 10, setup: ["power"])
        XCTAssertTrue(setup.hasStartingState)
    }

    func testScoring() {
        XCTAssertEqual(ExerciseScoring.timePenalty(elapsed: 100, target: 100), 0)
        XCTAssertEqual(ExerciseScoring.timePenalty(elapsed: 120, target: 100), 10)
        XCTAssertEqual(ExerciseScoring.timePenalty(elapsed: 400, target: 100), 30)
        XCTAssertEqual(ExerciseScoring.stars(score: 95), 3)
        XCTAssertEqual(ExerciseScoring.stars(score: 80), 2)
        XCTAssertEqual(ExerciseScoring.stars(score: 60), 1)
        XCTAssertEqual(ExerciseScoring.stars(score: 10), 0)
    }
}
