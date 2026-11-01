import XCTest
@testable import XPlaneKit

final class DispatchTests: XCTestCase {
    func testParsesVoiceStyleATIS() {
        let atis = ATISInfo.parse("""
        Madrid Barajas information Bravo, time 1030. Runway in use 36L for departure.
        Wind 340/12 knots. Visibility 10 km. Temperature 14, dewpoint 5. QNH 1018. Transition level 130.
        """)
        XCTAssertEqual(atis.letter, "B")
        XCTAssertEqual(atis.runway, "36L")
        XCTAssertEqual(atis.windDirection, 340)
        XCTAssertEqual(atis.windSpeed, 12)
        XCTAssertEqual(atis.temperature, 14)
        XCTAssertEqual(atis.qnh, 1018)
        XCTAssertEqual(atis.transitionLevel, 130)
    }

    func testParsesMETARStyleATIS() {
        let atis = ATISInfo.parse("LEBL ATIS INFO K 1030Z RWY 24R 25015G27KT 9999 FEW030 08/M02 Q1009 TL 70")
        XCTAssertEqual(atis.letter, "K")
        XCTAssertEqual(atis.runway, "24R")
        XCTAssertEqual(atis.windDirection, 250)
        XCTAssertEqual(atis.windSpeed, 15)
        XCTAssertEqual(atis.gust, 27)
        XCTAssertEqual(atis.temperature, 8)
        XCTAssertEqual(atis.dewpoint, -2)
        XCTAssertEqual(atis.qnh, 1009)
        XCTAssertEqual(atis.transitionLevel, 70)
        XCTAssertEqual(ATISInfo.parse("KJFK ATIS A2992").qnh, 1013)
        XCTAssertTrue(ATISInfo.parse("").isEmpty)
    }

    func testDutyPeriod() {
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 7 * 60, sectors: 2), 13 * 60)
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 7 * 60, sectors: 4), 12 * 60)
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 14 * 60, sectors: 2), 12 * 60 + 30)
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 22 * 60, sectors: 2), 11 * 60)
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 22 * 60, sectors: 10), 9 * 60)
        XCTAssertEqual(DutyPeriod.maximumMinutes(reportMinuteOfDay: 5 * 60 + 20, sectors: 1), 12 * 60 + 15)
    }

    func testSIDConstraints() {
        let atOrAbove = AltitudeConstraint(fix: "NANDO", kind: .atOrAbove, altitude: 5000, speed: 220)
        XCTAssertTrue(atOrAbove.violations(altitude: 5600, speed: 215).isEmpty)
        XCTAssertEqual(atOrAbove.violations(altitude: 4400, speed: 245).count, 2)
        let atOrBelow = AltitudeConstraint(fix: "PINAR", kind: .atOrBelow, altitude: 7000)
        XCTAssertTrue(atOrBelow.violations(altitude: 7200, speed: nil).isEmpty)
        XCTAssertEqual(atOrBelow.violations(altitude: 7600, speed: nil).count, 1)
        XCTAssertEqual(atOrAbove.text, "NANDO A5000 (o más) · máx 220 kt")
    }

    func testLevelBust() {
        var monitor = LevelBustMonitor()
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertNil(monitor.update(altitude: 6000, selected: 7000, at: t0))
        XCTAssertNil(monitor.update(altitude: 6950, selected: 7000, at: t0.addingTimeInterval(10)))
        XCTAssertNil(monitor.update(altitude: 7000, selected: 7000, at: t0.addingTimeInterval(16)))
        XCTAssertEqual(monitor.update(altitude: 7400, selected: 7000, at: t0.addingTimeInterval(30)), 400)
        XCTAssertNil(monitor.update(altitude: 7500, selected: 7000, at: t0.addingTimeInterval(31)), "warned once")
        XCTAssertNil(monitor.update(altitude: 7500, selected: 11000, at: t0.addingTimeInterval(32)), "a new altitude is not a bust")
    }

    func testSquawkValidation() {
        var clearance = DepartureClearance()
        clearance.squawk = "4721"
        XCTAssertTrue(clearance.isSquawkValid)
        clearance.squawk = "4821"
        XCTAssertFalse(clearance.isSquawkValid)
    }

    func testCatalogs() {
        XCTAssertEqual(Set(MELItem.catalog.map(\.id)).count, MELItem.catalog.count)
        XCTAssertEqual(Set(WalkaroundPoint.route.map(\.id)).count, WalkaroundPoint.route.count)
    }
}
