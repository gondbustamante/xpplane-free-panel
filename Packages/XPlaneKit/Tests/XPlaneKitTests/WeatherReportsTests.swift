import XCTest
@testable import XPlaneKit

final class WeatherReportsTests: XCTestCase {
    /// 24 November 2026, 10:00 UTC.
    private let reference = Date(timeIntervalSince1970: 1_795_514_400)

    private func utc(day: Int, hour: Int) -> Date {
        Calendar.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testReferenceDate() {
        XCTAssertEqual(utc(day: 24, hour: 10), reference)
    }

    func testCAVOKMETAR() throws {
        let metar = try XCTUnwrap(METARReport.decode("METAR LEMD 241030Z 02008KT CAVOK 12/M02 Q1021 NOSIG"))
        XCTAssertEqual(metar.station, "LEMD")
        let c = metar.conditions
        XCTAssertEqual(c.windDirection, 20)
        XCTAssertEqual(c.windSpeed, 8)
        XCTAssertEqual(c.visibility, 10_000)
        XCTAssertTrue(c.cavok)
        XCTAssertEqual(c.temperature, 12)
        XCTAssertEqual(c.dewpoint, -2)
        XCTAssertEqual(c.qnh, 1021)
        XCTAssertEqual(c.category, .vfr)
    }

    func testIFRWithGustAndRain() throws {
        let c = try XCTUnwrap(METARReport.decode("EGLL 241020Z 24015G28KT 3000 -RA BR BKN008 OVC015 09/08 Q1008")).conditions
        XCTAssertEqual(c.gust, 28)
        XCTAssertEqual(c.visibility, 3000)
        XCTAssertEqual(c.weather, ["-RA", "BR"])
        XCTAssertEqual(c.ceiling, 800)
        XCTAssertEqual(c.category, .ifr)
        XCTAssertFalse(c.hasThunderstorm)
    }

    func testAmericanMETAR() throws {
        let c = try XCTUnwrap(METARReport.decode("KJFK 241051Z 31012KT 1 1/2SM BR OVC004 M01/M03 A2992 RMK AO2")).conditions
        XCTAssertEqual(c.visibility, 2413)
        XCTAssertEqual(c.ceiling, 400)
        XCTAssertEqual(c.qnh, 1013)
        XCTAssertEqual(c.temperature, -1)
        XCTAssertEqual(c.category, .lifr)
    }

    func testTrendIsNotTheObservation() throws {
        let c = try XCTUnwrap(METARReport.decode("LEBL 241030Z 24010KT 9999 FEW030 15/08 Q1015 TEMPO 2000 TSRA")).conditions
        XCTAssertEqual(c.visibility, 10_000)
        XCTAssertFalse(c.hasThunderstorm)
    }

    private let taf = "TAF LEBL 241100Z 2412/2518 24012KT 9999 FEW030 TEMPO 2414/2418 4000 TSRA BKN020CB BECMG 2420/2422 VRB03KT FM250600 30010KT CAVOK"

    func testTAFGroups() throws {
        let report = try XCTUnwrap(TAFReport.decode(taf, reference: reference))
        XCTAssertEqual(report.station, "LEBL")
        XCTAssertEqual(report.groups.map(\.change), [.base, .temporary, .becoming, .from])
        XCTAssertEqual(report.groups[0].start, utc(day: 24, hour: 12))
        XCTAssertEqual(report.groups[0].end, utc(day: 25, hour: 6), "the base runs until the FM group")
        XCTAssertEqual(report.groups[1].start, utc(day: 24, hour: 14))
        XCTAssertEqual(report.groups[1].end, utc(day: 24, hour: 18))
        XCTAssertEqual(report.groups[3].start, utc(day: 25, hour: 6))
    }

    func testWorstAtTheArrivalTime() throws {
        let report = try XCTUnwrap(TAFReport.decode(taf, reference: reference))
        let afternoon = try XCTUnwrap(report.worst(from: utc(day: 24, hour: 15), to: utc(day: 24, hour: 16)))
        XCTAssertTrue(afternoon.hasThunderstorm)
        XCTAssertEqual(afternoon.visibility, 4000)
        XCTAssertEqual(afternoon.ceiling, 2000)
        XCTAssertEqual(afternoon.category, .ifr)
        let nextMorning = try XCTUnwrap(report.worst(from: utc(day: 25, hour: 8), to: utc(day: 25, hour: 9)))
        XCTAssertEqual(nextMorning.category, .vfr)
        XCTAssertEqual(nextMorning.windDirection, 300)
        XCTAssertFalse(nextMorning.hasThunderstorm)
    }

    func testTAFAcrossTheMonthEnd() throws {
        let lastDay = Calendar.utc.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 18))!
        let report = try XCTUnwrap(TAFReport.decode("TAF LEMD 301700Z 3018/0124 27010KT 9999 SCT040", reference: lastDay))
        XCTAssertEqual(report.groups[0].end, Calendar.utc.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 0)))
    }

    func testRunwayWind() throws {
        let cross = try XCTUnwrap(RunwayWind.components(runway: "25R", direction: 240, speed: 12, gust: nil))
        XCTAssertEqual(cross.crosswind, -2.08, accuracy: 0.05, "from the left")
        XCTAssertEqual(cross.headwind, 11.8, accuracy: 0.1)
        XCTAssertFalse(cross.exceedsLimits)
        let tail = try XCTUnwrap(RunwayWind.components(runway: "07", direction: 250, speed: 12, gust: nil))
        XCTAssertEqual(tail.headwind, -12, accuracy: 0.1)
        XCTAssertTrue(tail.exceedsLimits)
        let gusty = try XCTUnwrap(RunwayWind.components(runway: "36", direction: 90, speed: 30, gust: 42))
        XCTAssertEqual(gusty.crosswind, 42, accuracy: 0.1, "the gust counts")
        XCTAssertTrue(gusty.exceedsLimits)
        XCTAssertNil(RunwayWind.components(runway: "36", direction: nil, speed: 3, gust: nil), "variable wind")
    }
}
