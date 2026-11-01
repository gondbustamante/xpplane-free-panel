import XCTest
@testable import XPlaneKit

final class GroundTests: XCTestCase {
    private let tobt = Date(timeIntervalSince1970: 1_800_000_000)

    func testACDMWindowAndTOBTUpdate() {
        var times = ACDMTimes(tobt: tobt, taxiMinutes: 12)
        XCTAssertEqual(times.startup, tobt, "until the TSAT arrives the TOBT counts")
        times.tsat = tobt.addingTimeInterval(10 * 60)
        XCTAssertEqual(times.ttot, tobt.addingTimeInterval(22 * 60))
        XCTAssertEqual(times.status(at: tobt, expectedReady: nil), .waiting(minutes: 5))
        XCTAssertEqual(times.status(at: tobt.addingTimeInterval(9 * 60), expectedReady: nil), .window(minutesLeft: 6))
        XCTAssertEqual(times.status(at: tobt.addingTimeInterval(16 * 60), expectedReady: nil), .missed)
        XCTAssertEqual(times.status(at: tobt, expectedReady: tobt.addingTimeInterval(8 * 60)), .updateTOBT(8))
        XCTAssertEqual(times.status(at: tobt, expectedReady: tobt.addingTimeInterval(4 * 60)), .waiting(minutes: 5),
                       "within 5 minutes the TOBT stands")
    }

    func testHoldoverTimes() {
        XCTAssertEqual(Deicing.holdover(fluid: .typeIV, condition: .lightSnow, temperature: 0), 45...75)
        XCTAssertEqual(Deicing.holdover(fluid: .typeIV, condition: .lightSnow, temperature: -10), 30...60)
        XCTAssertNil(Deicing.holdover(fluid: .typeIV, condition: .frost, temperature: -30), "below the fluid's LOUT")
        for condition in Deicing.Condition.allCases {
            let one = Deicing.holdover(fluid: .typeI, condition: condition, temperature: 0)!
            let four = Deicing.holdover(fluid: .typeIV, condition: condition, temperature: 0)!
            XCTAssertLessThan(one.upperBound, four.upperBound, "Type IV protects longer: \(condition)")
        }
        let left = Deicing.remaining(start: tobt, holdover: 45...75, at: tobt.addingTimeInterval(50 * 60))
        XCTAssertEqual(left.toMinimum, -5)
        XCTAssertEqual(left.toMaximum, 25)
    }

    func testSingleEngineTaxi() {
        XCTAssertEqual(Taxi.secondEngineStart(takeoff: tobt), tobt.addingTimeInterval(-5 * 60))
        XCTAssertEqual(Taxi.singleEngineSaving(minutes: 15), 50)
        XCTAssertEqual(Taxi.singleEngineSaving(minutes: 3), 0)
    }

    func testCrossTrack() {
        // Track due north along the meridian 0; a point 0.1° east is about 6 NM right.
        let xtk = Geo.crossTrack(latitude: 1, longitude: 0.1, from: (0, 0), to: (2, 0))
        XCTAssertEqual(xtk, 6.0, accuracy: 0.1)
        XCTAssertLessThan(Geo.crossTrack(latitude: 1, longitude: -0.1, from: (0, 0), to: (2, 0)), 0)
    }

    func testDescentWind() {
        // FL350 to sea level at 2200 ft/min is about 16 min; 30 kt of tailwind at 60 % ≈ 4.8 NM.
        XCTAssertEqual(DescentProfile.windCorrection(altitude: 35000, destinationElevation: 0, tailwind: 30), 4.77, accuracy: 0.05)
        XCTAssertLessThan(DescentProfile.windCorrection(altitude: 35000, destinationElevation: 0, tailwind: -30), 0)
    }

    func testLandingDistance() {
        let medium = LandingDistance.estimate(weightKg: 60_000, elevationFt: 0, headwind: 0, braking: .medium, surface: .dry)
        let low = LandingDistance.estimate(weightKg: 60_000, elevationFt: 0, headwind: 0, braking: .low, surface: .dry)
        XCTAssertEqual(medium, 1200, accuracy: 60)
        XCTAssertGreaterThan(low, medium)
        XCTAssertGreaterThan(LandingDistance.estimate(weightKg: 60_000, elevationFt: 0, headwind: 0, braking: .medium, surface: .standingWater), medium)
        XCTAssertGreaterThan(LandingDistance.estimate(weightKg: 60_000, elevationFt: 0, headwind: -10, braking: .medium, surface: .dry), medium)
        XCTAssertLessThan(LandingDistance.estimate(weightKg: 60_000, elevationFt: 0, headwind: 20, braking: .medium, surface: .dry), medium)
        XCTAssertEqual(LandingDistance.factored(1000), 1150, accuracy: 0.001)
    }
}
