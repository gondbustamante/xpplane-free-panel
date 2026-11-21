import XCTest
@testable import XPlaneKit

final class ATCScriptTests: XCTestCase {
    private var input: ATCInput {
        var input = ATCInput(callsign: "IBE3742", origin: "LEMD", originCity: "Madrid", destination: "LEBL",
                             destinationCity: "Barcelona", initialClimb: 6000, cruise: 35_000, squawk: "4521")
        input.departureRunway = "36L"
        input.arrivalRunway = "25R"
        input.sid = "NANDO1A"
        input.star = "LOBAR1Q"
        input.departureATIS = "D"
        input.departureQNH = 1018
        input.arrivalQNH = 1012
        input.departureWind = (350, 8)
        input.arrivalWind = (240, 12)
        input.departureFrequency = "127.500"
        input.destinationElevation = 14
        return input
    }

    func testRadiotelephony() {
        XCTAssertEqual(Radio.flightLevel(feet: 35_000), Phrase("FL350", spoken: "flight level three five zero"))
        XCTAssertEqual(Radio.altitude(feet: 6000).spoken, "six thousand feet")
        XCTAssertEqual(Radio.altitude(feet: 4500).spoken, "four thousand five hundred feet")
        XCTAssertEqual(Radio.runway("36L").spoken, "three six left")
        XCTAssertEqual(Radio.runway("07").spoken, "zero seven")
        XCTAssertEqual(Radio.frequency("118.705").spoken, "one one eight decimal seven zero five")
        XCTAssertEqual(Radio.qnh(1009).spoken, "QNH one zero zero niner")
        XCTAssertEqual(Radio.procedure("NANDO1A").spoken, "Nando one Alpha")
        XCTAssertEqual(Radio.callsign("IBE3742"), Phrase("Iberia 3742", spoken: "Iberia three seven four two"))
        XCTAssertEqual(Radio.callsign("XYZ12").spoken, "X-ray Yankee Zulu one two", "unknown airline spelled out")
        XCTAssertEqual(Radio.wind(direction: 50, speed: 8)?.display, "wind 050/8 kt")
        XCTAssertEqual(Radio.level(feet: 6000, transitionAltitude: 6000).display, "6000 ft")
        XCTAssertEqual(Radio.level(feet: 7000, transitionAltitude: 6000).display, "FL070")
    }

    func testWholeFlightInOrder() {
        let script = ATCScript.make(input)
        XCTAssertEqual(script.first?.phase, .clearance)
        XCTAssertEqual(script.last?.phase, .taxiIn)
        let phases = script.map(\.phase)
        XCTAssertEqual(phases, phases.sorted { ATCExchange.Phase.allCases.firstIndex(of: $0)! < ATCExchange.Phase.allCases.firstIndex(of: $1)! },
                       "phases never go back")
        XCTAssertEqual(Set(script.map(\.id)).count, script.count)
        XCTAssertTrue(script.allSatisfy { !$0.calls.isEmpty })
    }

    func testClearanceCarriesThePlan() throws {
        let clearance = try XCTUnwrap(ATCScript.make(input).first)
        XCTAssertEqual(clearance.station, "Madrid Delivery")
        let atc = clearance.calls[1].text.display
        XCTAssertTrue(atc.contains("cleared to Barcelona via NANDO1A departure"))
        XCTAssertTrue(atc.contains("runway 36L"))
        XCTAssertTrue(atc.contains("climb 6000 ft"))
        XCTAssertTrue(atc.contains("squawk 4521"))
        XCTAssertTrue(clearance.calls[0].text.spoken.contains("information Delta"))
        XCTAssertEqual(clearance.actions, [.squawk("4521"), .altitude(6000)])
    }

    func testLevelsClimbToCruiseAndDescend() {
        let script = ATCScript.make(input)
        let altitudes = script.flatMap(\.actions).compactMap { action -> Int? in
            if case .altitude(let feet) = action { return feet }
            return nil
        }
        XCTAssertEqual(altitudes, [6000, 15_000, 35_000, 10_000, 3_000])
        XCTAssertTrue(script.contains { $0.calls.contains { $0.text.display.contains("cleared LOBAR1Q arrival, runway 25R") } })
        XCTAssertTrue(script.contains { $0.calls.contains { $0.text.display.contains("cleared to land") } })
    }

    func testHandOffsUseTheStations() {
        let script = ATCScript.make(input)
        let stations = script.map(\.station)
        XCTAssertTrue(stations.contains("Madrid Departure"))
        XCTAssertTrue(stations.contains("Barcelona Control"))
        XCTAssertTrue(stations.contains("Barcelona Approach"))
        let handOff = script.first { $0.title == "Cambio a salidas" }
        XCTAssertEqual(handOff?.calls.first?.text.display, "Iberia 3742, contact Madrid Departure 127.500. Good bye.")
        XCTAssertTrue(handOff?.startsWithController == true)
    }

    func testSameCityHasNoCentreChange() {
        var domestic = input
        domestic.destinationCity = "Madrid"
        XCTAssertFalse(ATCScript.make(domestic).contains { $0.title == "Cambio de centro" })
    }

    func testMissingDataStillMakesAScript() {
        var bare = ATCInput(callsign: "N123AB", origin: "KXYZ", originCity: "Springfield", destination: "KABC",
                            destinationCity: "Shelbyville", initialClimb: 5000, cruise: 9000, squawk: "1234")
        bare.hasILS = false
        let script = ATCScript.make(bare)
        XCTAssertTrue(script[0].calls[1].text.display.contains("via flight planned route"))
        XCTAssertTrue(script.contains { $0.calls.contains { $0.text.display.contains("RNP") } })
    }

    func testGeneratedSquawk() {
        let code = ATCScript.squawk(for: "IBE3742LEMDLEBL")
        XCTAssertEqual(code.count, 4)
        XCTAssertTrue(code.allSatisfy { ("0"..."7").contains($0) })
        XCTAssertEqual(code, ATCScript.squawk(for: "IBE3742LEMDLEBL"), "stable for the same flight")
        XCTAssertFalse(["7500", "7600", "7700"].contains(code))
    }

    func testCityNames() {
        XCTAssertEqual(Radio.city(icao: "LEMD", airportName: "Adolfo Suarez Madrid-Barajas"), "Madrid")
        XCTAssertEqual(Radio.city(icao: "XXXX", airportName: "Aeropuerto de Logroño-Agoncillo"), "Logroño")
        XCTAssertEqual(Radio.city(icao: "KXYZ", airportName: "Springfield Regional Airport"), "Springfield")
        XCTAssertEqual(Radio.city(icao: "ZZZZ", airportName: nil), "ZZZZ")
    }
}
