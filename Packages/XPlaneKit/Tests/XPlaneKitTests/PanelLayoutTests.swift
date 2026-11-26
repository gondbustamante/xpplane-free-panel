import XCTest
@testable import XPlaneKit

final class PanelLayoutTests: XCTestCase {
    func testDecodesAreasAndFiltersThemByGroup() throws {
        let json = """
        {
          "groups": [{ "id": "overhead", "title": "Overhead" }],
          "phases": [],
          "areas": [
            { "id": "overhead_center", "title": "Panel central", "group": "overhead", "subpanels": ["fire", "hyd"] },
            { "id": "other", "title": "Otra", "group": "pedestal", "subpanels": ["rmp1"] }
          ]
        }
        """
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.areas(in: "overhead").map(\.id), ["overhead_center"])
        XCTAssertEqual(layout.areas(in: "overhead").first?.subpanels, ["fire", "hyd"])
        XCTAssertNil(layout.areas(in: "overhead").first?.icon)
    }

    func testAreaArrangementIsOptionalAndNamesThePedestalLayout() throws {
        let json = """
        {
          "groups": [], "phases": [],
          "areas": [
            { "id": "pedestal_full", "title": "Pedestal completo", "group": "pedestal",
              "arrangement": "pedestal", "subpanels": ["mcdu", "ecp", "rmp1"] },
            { "id": "overhead_center", "title": "Panel central", "group": "overhead", "subpanels": ["fire"] }
          ]
        }
        """
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.areas(in: "pedestal").first?.isPedestal, true)
        XCTAssertEqual(layout.areas(in: "pedestal").first?.subpanels.first, "mcdu")
        XCTAssertEqual(layout.areas(in: "overhead").first?.isPedestal, false)
    }

    func testAreasAreOptional() throws {
        let json = #"{ "groups": [], "phases": [] }"#
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertTrue(layout.areas(in: "overhead").isEmpty)
    }
}
