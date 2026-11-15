import XCTest
@testable import XPlaneKit

final class VerticalProfileTests: XCTestCase {
    private func fix(_ ident: String, _ longitude: Double, _ altitude: Int?, type: String = "wpt") -> SimBriefOFP.NavFix {
        SimBriefOFP.NavFix(ident: ident, type: type, latitude: 0, longitude: longitude, legDistance: nil, altitude: altitude,
                           plannedFuel: nil, minimumFuel: nil, timeTotal: nil, stage: nil)
    }

    /// Along the equator, one degree (≈60 NM) between points: climb, cruise, descent.
    private var profile: VerticalProfile {
        VerticalProfile(
            fixes: [fix("SID01", 0.5, 8000), fix("TOC", 1, 36000, type: "ltlg"), fix("MID", 2, 36000),
                    fix("TOD", 3, 36000, type: "ltlg"), fix("STAR1", 3.5, 10000)],
            origin: .init(ident: "AAAA", latitude: 0, longitude: 0, elevation: 2000),
            destination: .init(ident: "BBBB", latitude: 0, longitude: 4, elevation: 100))
    }

    func testPlannedProfileAndLandmarks() {
        let profile = profile
        XCTAssertEqual(profile.planned.count, 7)
        XCTAssertEqual(profile.planned.first!.distance, -30, accuracy: 0.5, "origin before the first navlog point")
        XCTAssertEqual(profile.planned.first!.altitude, 2000)
        XCTAssertEqual(profile.routeLength, 180, accuracy: 1)
        XCTAssertEqual(profile.destinationDistance, 210, accuracy: 1)
        XCTAssertEqual(profile.landmarks.compactMap(\.label), ["AAAA", "TOC", "TOD", "BBBB"])
    }

    func testDistanceAlongMatchesTheRoute() throws {
        let along = try XCTUnwrap(profile.distanceAlong(latitude: 0, longitude: 1.5))
        XCTAssertEqual(along, 60, accuracy: 1, "halfway between TOC and MID")
    }

    func testPlannedAltitudeInterpolates() {
        XCTAssertEqual(profile.plannedAltitude(at: 15)!, 22_000, accuracy: 300, "halfway up the climb")
        XCTAssertEqual(profile.plannedAltitude(at: 90)!, 36_000)
    }

    func testDescentPath() {
        let path = profile.descentPath(ceiling: 36_000)
        XCTAssertEqual(path.last!.distance, 210 - (35_900 / 1000 * 3 + 10), accuracy: 1)
        XCTAssertEqual(path.last!.altitude, 36_000)
    }

    func testProjectionLevelsOffAtTheFCUAltitude() {
        // 1800 ft/min at 300 kt: 360 ft per NM, 5000 ft to go → level in about 14 NM.
        let path = VerticalProfile.projection(distance: 40, altitude: 15_000, groundspeed: 300, verticalSpeed: 1800,
                                              selectedAltitude: 20_000, ahead: 50)
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path[1].distance, 40 + 5000.0 / 360, accuracy: 0.1)
        XCTAssertEqual(path[1].altitude, 20_000)
        XCTAssertEqual(path[2].distance, 90)
    }

    func testProjectionAwayFromTheFCUAltitudeKeepsGoing() {
        let path = VerticalProfile.projection(distance: 0, altitude: 15_000, groundspeed: 300, verticalSpeed: -1200,
                                              selectedAltitude: 20_000, ahead: 20)
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(path[1].altitude, 15_000 - 240 * 20, accuracy: 1)
    }

    func testNoProjectionOnTheGround() {
        XCTAssertTrue(VerticalProfile.projection(distance: 0, altitude: 0, groundspeed: 20, verticalSpeed: 0,
                                                 selectedAltitude: 5000, ahead: 20).isEmpty)
    }
}
