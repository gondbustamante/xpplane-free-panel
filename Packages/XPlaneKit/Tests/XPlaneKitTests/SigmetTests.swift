import XCTest
@testable import XPlaneKit

final class SigmetTests: XCTestCase {
    /// A square between longitudes 1 and 2 on the equator, FL300 to FL380.
    private let json = """
    [
      {"icaoId": "LECM", "firId": "LECM", "firName": "MADRID", "seriesId": "A3", "hazard": "TURB", "qualifier": "SEV",
       "base": 30000, "top": 38000, "validTimeFrom": 1795510800, "validTimeTo": 1795525200,
       "coords": [{"lat": -0.5, "lon": 1.0}, {"lat": 0.5, "lon": 1.0}, {"lat": 0.5, "lon": 2.0}, {"lat": -0.5, "lon": 2.0}],
       "rawSigmet": "LECM SIGMET A3 VALID 241000/241400 SEV TURB FL300/380"},
      {"icaoId": "LFFF", "hazard": "ICE", "base": null, "top": 12000, "coords": []},
      {"icaoId": "LFFF", "hazard": "TS", "qualifier": "EMBD", "top": "40000",
       "coords": [{"lat": "10", "lon": "10"}, {"lat": "11", "lon": "10"}, {"lat": "11", "lon": "11"}]}
    ]
    """

    private func fix(_ ident: String, _ longitude: Double, _ altitude: Int) -> SimBriefOFP.NavFix {
        SimBriefOFP.NavFix(ident: ident, type: "wpt", latitude: 0, longitude: longitude, legDistance: nil, altitude: altitude,
                           plannedFuel: nil, minimumFuel: nil, timeTotal: nil, stage: nil)
    }

    func testDecode() throws {
        let sigmets = Sigmet.decode(json: Data(json.utf8))
        XCTAssertEqual(sigmets.count, 2, "the one without an area is skipped")
        let turbulence = try XCTUnwrap(sigmets.first)
        XCTAssertEqual(turbulence.hazard, .turbulence)
        XCTAssertEqual(turbulence.title, "Fuerte turbulencia")
        XCTAssertEqual(turbulence.base, 30000)
        XCTAssertEqual(turbulence.top, 38000)
        XCTAssertEqual(turbulence.fir, "MADRID")
        XCTAssertEqual(turbulence.validTo, Date(timeIntervalSince1970: 1795525200))
        XCTAssertEqual(sigmets[1].hazard, .thunderstorm)
        XCTAssertEqual(sigmets[1].top, 40000, "numbers given as text")
        XCTAssertTrue(Sigmet.decode(json: Data("not json".utf8)).isEmpty)
    }

    func testContainsAndLevels() throws {
        let sigmet = try XCTUnwrap(Sigmet.decode(json: Data(json.utf8)).first)
        XCTAssertTrue(sigmet.contains(latitude: 0, longitude: 1.5))
        XCTAssertFalse(sigmet.contains(latitude: 0, longitude: 2.5))
        XCTAssertTrue(sigmet.overlaps(lower: 35_000, upper: 35_000))
        XCTAssertFalse(sigmet.overlaps(lower: 20_000, upper: 25_000))
    }

    func testHazardsAlongTheRoute() throws {
        let sigmets = Sigmet.decode(json: Data(json.utf8))
        let fixes = [fix("A", 0, 35_000), fix("B", 3, 35_000)]
        let profile = VerticalProfile(fixes: fixes, origin: nil, destination: nil)
        let now = Date(timeIntervalSince1970: 1795514400)
        let hazards = RouteHazard.along(profile, fixes: fixes, sigmets: sigmets, now: now)
        XCTAssertEqual(hazards.count, 1, "the thunderstorms are far from the route")
        let hazard = try XCTUnwrap(hazards.first)
        XCTAssertEqual(hazard.entry, 60, accuracy: 6)
        XCTAssertEqual(hazard.exit, 120, accuracy: 6)
        XCTAssertTrue(hazard.atPlannedLevels)

        let low = [fix("A", 0, 20_000), fix("B", 3, 20_000)]
        let below = RouteHazard.along(VerticalProfile(fixes: low, origin: nil, destination: nil), fixes: low,
                                      sigmets: sigmets, now: now)
        XCTAssertEqual(below.first?.atPlannedLevels, false, "the route passes under it")
        XCTAssertTrue(RouteHazard.along(profile, fixes: fixes, sigmets: sigmets,
                                        now: Date(timeIntervalSince1970: 1795530000)).isEmpty, "expired")
    }

    // MARK: Winds aloft

    func testWindAgainstThePlan() throws {
        // Flying east along the equator; the plan had 270/60 (a tailwind), the sim gives 090/30.
        var a = fix("A", 0, 35_000), b = fix("B", 1, 35_000)
        a.windDirection = 270; a.windSpeed = 60; a.isaDeviation = 5
        b.windDirection = 270; b.windSpeed = 60; b.isaDeviation = 5
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 0.5, on: [a, b]))
        let comparison = try XCTUnwrap(WindComparison.compare(progress: progress, fixes: [a, b], windDirection: 90,
                                                              windSpeed: 30, temperature: -44, altitude: 35_000))
        XCTAssertEqual(comparison.plannedHeadwind, -60, accuracy: 0.5)
        XCTAssertEqual(comparison.actualHeadwind, 30, accuracy: 0.5)
        XCTAssertEqual(comparison.headwindChange, 90, accuracy: 1)
        XCTAssertEqual(comparison.plannedISADeviation, 5)
        XCTAssertEqual(comparison.actualISADeviation!, -44 - (15 - 1.98 * 35), accuracy: 0.01)
    }

    func testWindsInterpolateAsVectors() throws {
        var a = fix("A", 0, 35_000), b = fix("B", 1, 35_000)
        a.windDirection = 350; a.windSpeed = 40
        b.windDirection = 10; b.windSpeed = 40
        let progress = try XCTUnwrap(RouteProgress.locate(latitude: 0, longitude: 0.5, on: [a, b]))
        let comparison = try XCTUnwrap(WindComparison.compare(progress: progress, fixes: [a, b], windDirection: 0,
                                                              windSpeed: 40, temperature: nil, altitude: 35_000))
        XCTAssertTrue(comparison.plannedDirection < 1 || comparison.plannedDirection > 359, "about north, not south")
    }
}
