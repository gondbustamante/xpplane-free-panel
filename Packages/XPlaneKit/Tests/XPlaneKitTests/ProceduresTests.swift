import XCTest
@testable import XPlaneKit

final class ProceduresTests: XCTestCase {
    private let json = """
    {
      "id": "normal", "title": "Normal",
      "procedures": [
        { "id": "prep", "kind": "flow", "title": "Preparación", "phase": "cold_dark",
          "items": [
            { "challenge": "ADIRS 1, 2", "response": "NAV",
              "checks": [ { "control": "adirs.ir1", "expect": ["NAV"] }, { "control": "adirs.ir2", "expect": ["NAV"] } ] },
            { "challenge": "MCDU", "response": "PREPARED", "panels": ["mcdu"] },
            { "challenge": "FLAPS", "response": "SET", "optional": true,
              "checks": [ { "control": "flaps.lever", "expect": ["1", "2", "3"] } ] }
          ] }
      ]
    }
    """

    private func book() throws -> ProcedureBook {
        try JSONDecoder().decode(ProcedureBook.self, from: Data(json.utf8))
    }

    func testDecodesFlowItemsAndChecks() throws {
        let procedure = try XCTUnwrap(book().procedures.first)
        XCTAssertEqual(procedure.kind, .flow)
        XCTAssertEqual(procedure.items.count, 3)
        XCTAssertTrue(procedure.items[0].isSensed)
        XCTAssertFalse(procedure.items[1].isSensed)
        XCTAssertTrue(procedure.items[2].isOptional)
    }

    func testSensedStateNeedsEveryControl() throws {
        let item = try book().procedures[0].items[0]
        XCTAssertEqual(item.sensedState { _ in "NAV" }, .satisfied)
        XCTAssertEqual(item.sensedState { $0 == "adirs.ir1" ? "NAV" : nil }, .unknown)
        XCTAssertEqual(item.sensedState { $0 == "adirs.ir1" ? "OFF" : nil }, .unsatisfied)
        XCTAssertEqual(try book().procedures[0].items[1].sensedState { _ in "NAV" }, .notSensed)
    }

    func testAnyExpectedPositionSatisfies() throws {
        let item = try book().procedures[0].items[2]
        XCTAssertEqual(item.sensedState { _ in "2" }, .satisfied)
        XCTAssertEqual(item.sensedState { _ in "0" }, .unsatisfied)
    }

    func testPanelsInItemOrderWithoutRepeats() throws {
        let panels = try book().procedures[0].panels { control in
            control.hasPrefix("adirs") ? "adirs" : (control.hasPrefix("flaps") ? "flaps" : nil)
        }
        XCTAssertEqual(panels, ["adirs", "mcdu", "flaps"])
    }
}

final class BaroBindingTests: XCTestCase {
    func testWindowText() {
        XCTAssertEqual(BaroBinding.text(inHg: 29.92, std: 1, hectopascal: 1), "Std")
        XCTAssertEqual(BaroBinding.text(inHg: 29.92, std: 0, hectopascal: 1), "1013")
        XCTAssertEqual(BaroBinding.text(inHg: 29.92, std: 0, hectopascal: 0), "29.92")
        XCTAssertNil(BaroBinding.text(inHg: nil, std: 0, hectopascal: 0))
    }

    func testDecodesBaroAndPull() throws {
        let json = """
        { "id": "efis.baro", "label": "", "kind": "dualKnob", "positions": ["", ""],
          "commands": { "up": "a", "down": "b", "press": "push", "pull": "pull" },
          "baro": { "std": "AirbusFBW/BaroStdCapt", "unit": "AirbusFBW/BaroUnitCapt" } }
        """
        let control = try JSONDecoder().decode(ControlDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(control.commands?.pull, "pull")
        XCTAssertEqual(control.baro?.unit, "AirbusFBW/BaroUnitCapt")
    }
}
