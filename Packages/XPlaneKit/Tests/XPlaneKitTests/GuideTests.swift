import XCTest
@testable import XPlaneKit

final class GuideTests: XCTestCase {
    private let json = """
    {
      "id": "systems", "title": "Sistemas",
      "systems": [
        { "id": "apu", "title": "APU", "panels": ["apu"], "summary": "Motor auxiliar.", "ecam": "APU" }
      ],
      "explanations": [
        { "controls": ["apu.master"], "what": "Prepara el APU.",
          "positions": { "ON": "Abre la toma de aire.", "OFF": "Para el APU." } },
        { "controls": ["rmp1.vhf1", "rmp2.vhf1"], "title": "VHF 1", "what": "Selecciona VHF 1." }
      ]
    }
    """

    private let second = """
    { "id": "extra", "title": "Extra",
      "explanations": [ { "controls": ["apu.master"], "what": "Otra explicación." } ] }
    """

    private func book(_ text: String) throws -> GuideBook {
        try JSONDecoder().decode(GuideBook.self, from: Data(text.utf8))
    }

    func testLooksUpControlsAndSystems() throws {
        let guide = Guide(books: [try book(json)])
        XCTAssertEqual(guide.explanation(for: "apu.master")?.positions?["ON"], "Abre la toma de aire.")
        XCTAssertEqual(guide.explanation(for: "rmp2.vhf1")?.title, "VHF 1")
        XCTAssertNil(guide.explanation(for: "apu.start"))
        XCTAssertEqual(guide.system(forPanel: "apu")?.ecam, "APU")
        XCTAssertNil(guide.system(forPanel: "elec"))
        XCTAssertFalse(guide.isEmpty)
        XCTAssertTrue(Guide.empty.isEmpty)
    }

    func testFirstExplanationWins() throws {
        let guide = Guide(books: [try book(json), try book(second)])
        XCTAssertEqual(guide.explanation(for: "apu.master")?.what, "Prepara el APU.")
    }

    func testProcedureItemDecodesWhy() throws {
        let item = try JSONDecoder().decode(ProcedureItem.self, from: Data("""
        { "challenge": "INIT A", "response": "COMPLETE", "why": "El FMGS necesita origen y destino." }
        """.utf8))
        XCTAssertEqual(item.why, "El FMGS necesita origen y destino.")
    }
}
