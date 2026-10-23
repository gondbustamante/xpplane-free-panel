import XCTest
@testable import XPlaneKit

final class MCDUScreenTests: XCTestCase {
    private func b64(_ text: String) -> XPValue {
        .string(Data(text.utf8).base64EncodedString())
    }

    private func pad(_ text: String) -> String {
        text.padding(toLength: 24, withPad: " ", startingAt: 0)
    }

    func testHasTheHundredAndFiftyDatarefsOfTheDump() {
        let names = MCDUScreen.datarefNames(unit: 1)
        XCTAssertEqual(names.count, 150)
        XCTAssertEqual(Set(names).count, 150)
        XCTAssertTrue(names.contains("AirbusFBW/MCDU1label3Lg"))
        XCTAssertTrue(names.contains("AirbusFBW/MCDU1scont6y"))
        XCTAssertFalse(names.contains("AirbusFBW/MCDU1stitles"), "the dump has no small special title")
        XCTAssertTrue(MCDUScreen.datarefNames(unit: 2).allSatisfy { $0.hasPrefix("AirbusFBW/MCDU2") })
    }

    func testComposesRowsColoursAndSizes() {
        let values: [String: XPValue] = [
            "AirbusFBW/MCDU1titlew": b64(pad("          INIT")),
            "AirbusFBW/MCDU1label1w": b64(pad(" CO RTE         FROM/TO")),
            "AirbusFBW/MCDU1cont1a": b64(pad("##########     ####/####")),
            "AirbusFBW/MCDU1scont3b": b64(pad("                   36090")),
            "AirbusFBW/MCDU1spw": b64("KJFK\0garbage"),
        ]
        let screen = MCDUScreen.decode(unit: 1, values: values)
        XCTAssertEqual(screen.text(row: 0).trimmingCharacters(in: .whitespaces), "INIT")
        XCTAssertEqual(screen.cells[1][1].character, "C")
        XCTAssertTrue(screen.cells[1][1].small)
        XCTAssertEqual(screen.cells[2][0], MCDUCell(character: "☐", color: .amber, small: false))
        XCTAssertEqual(screen.cells[6][23].color, .cyan)
        XCTAssertTrue(screen.cells[6][23].small)
        XCTAssertEqual(screen.text(row: 13).trimmingCharacters(in: .whitespaces), "KJFK", "stops at NUL")
    }

    func testSpecialSymbols() {
        let values: [String: XPValue] = [
            "AirbusFBW/MCDU1cont2s": b64(pad("A    B               23")),
            "AirbusFBW/MCDU1cont4w": b64(pad("25`")),
        ]
        let screen = MCDUScreen.decode(unit: 1, values: values)
        XCTAssertEqual(screen.cells[4][0], MCDUCell(character: "[", color: .cyan, small: false))
        XCTAssertEqual(screen.cells[4][5].character, "]")
        XCTAssertEqual(screen.cells[4][21], MCDUCell(character: "←", color: .white, small: false))
        XCTAssertEqual(screen.cells[4][22], MCDUCell(character: "→", color: .white, small: false))
        XCTAssertEqual(screen.cells[8][2].character, "°")
    }

    func testSlewArrowsAndPlainStrings() {
        let values: [String: XPValue] = [
            "AirbusFBW/MCDU2VertSlewKeys": .number(1),
            "AirbusFBW/MCDU2titleg": .string("F-PLN WITH SPACES"),   // not base64 → plain text
        ]
        let screen = MCDUScreen.decode(unit: 2, values: values)
        XCTAssertTrue(screen.canSlewUp && screen.canSlewDown)
        XCTAssertEqual(screen.cells[13][22].character, "↑")
        XCTAssertEqual(screen.cells[13][23].character, "↓")
        XCTAssertTrue(screen.text(row: 0).hasPrefix("F-PLN WITH SPACES"))
        XCTAssertEqual(screen.cells[0][0].color, .green)
        XCTAssertTrue(MCDUScreen.decode(unit: 1, values: [:]).isBlank)
    }
}
