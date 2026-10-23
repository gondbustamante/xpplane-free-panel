import XCTest
@testable import XPlaneKit

final class WSMessagesTests: XCTestCase {
    func testDecodesDatarefUpdate() throws {
        let text = #"{"type":"dataref_update_values","data":{"123":[0,1,2],"456":1.5}}"#
        guard case .datarefUpdate(let values) = try WSIncoming.decode(text) else {
            return XCTFail("expected dataref update")
        }
        XCTAssertEqual(values[123], .array([.number(0), .number(1), .number(2)]))
        XCTAssertEqual(values[456], .number(1.5))
    }

    func testDecodesFailedResult() throws {
        let text = #"{"type":"result","req_id":4,"success":false,"error_code":"BAD_REQUEST","error_message":"nope"}"#
        guard case .result(let result) = try WSIncoming.decode(text) else {
            return XCTFail("expected result")
        }
        XCTAssertEqual(result.reqID, 4)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorCode, "BAD_REQUEST")
        XCTAssertEqual(result.errorMessage, "nope")
    }

    func testUnknownMessageTypeDoesNotThrow() throws {
        guard case .unknown(let type) = try WSIncoming.decode(#"{"type":"something_new"}"#) else {
            return XCTFail("expected unknown")
        }
        XCTAssertEqual(type, "something_new")
    }

    func testEncodesSubscribeRequestShape() throws {
        let request = WSRequest(req_id: 7, type: "dataref_subscribe_values",
                                params: WSSubscribeParams(datarefs: [WSDatarefRef(id: 42, index: nil)]))
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["req_id"] as? Int, 7)
        XCTAssertEqual(object["type"] as? String, "dataref_subscribe_values")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let refs = try XCTUnwrap(params["datarefs"] as? [[String: Any]])
        XCTAssertEqual(refs.first?["id"] as? Int, 42)
        XCTAssertNil(refs.first?["index"], "nil index must be omitted, not sent as null")
    }

    func testEncodesCommandActivation() throws {
        let request = WSRequest(req_id: 1, type: "command_set_is_active",
                                params: WSCommandParams(commands: [WSCommandActive(id: 9, is_active: true, duration: nil)]))
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let commands = try XCTUnwrap(params["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.first?["is_active"] as? Bool, true)
    }
}

final class XPValueTests: XCTestCase {
    func testElementAccess() {
        let array = XPValue.array([.number(0), .number(2)])
        XCTAssertEqual(array.element(at: 1)?.intValue, 2)
        XCTAssertNil(array.element(at: 5))
        XCTAssertEqual(XPValue.number(3).element(at: nil)?.intValue, 3)
    }

    func testIntegralNumbersEncodeWithoutDecimals() throws {
        let data = try JSONEncoder().encode(XPValue.number(2))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "2")
        let fractional = try JSONEncoder().encode(XPValue.number(0.5))
        XCTAssertEqual(String(decoding: fractional, as: UTF8.self), "0.5")
    }
}

final class PanelMappingTests: XCTestCase {
    private let sample = """
    {
      "id": "ext_lt", "title": "EXT LT", "order": 1,
      "controls": [
        {"id": "ext_lt.strobe", "label": "STROBE", "kind": "toggle3",
         "positions": ["OFF", "AUTO", "ON"],
         "state": {"dataref": "AirbusFBW/OHPLightSwitches", "index": 7},
         "col": 0, "row": 0, "verified": true},
        {"id": "ext_lt.land_l", "label": "LAND L", "kind": "toggle3",
         "positions": ["RETRACT", "OFF", "ON"],
         "state": {"dataref": "AirbusFBW/OHPLightSwitches", "index": 4, "values": [0, 1, 2]},
         "col": 1, "row": 0}
      ]
    }
    """

    func testDecodesSubpanel() throws {
        let panel = try JSONDecoder().decode(SubpanelDefinition.self, from: Data(sample.utf8))
        XCTAssertEqual(panel.controls.count, 2)
        XCTAssertTrue(panel.controls[0].isVerified)
        XCTAssertFalse(panel.controls[1].isVerified)
        XCTAssertEqual(panel.controls[0].writeBinding?.key.description, "AirbusFBW/OHPLightSwitches[7]")
    }

    func testPositionMappingIsNearestValue() {
        let binding = ValueBinding(dataref: "x", index: nil, values: [0, 1, 2], aliases: nil)
        XCTAssertEqual(binding.position(for: .number(1), count: 3), 1)
        XCTAssertEqual(binding.position(for: .number(1.9), count: 3), 2)
        XCTAssertNil(binding.position(for: .string("abc"), count: 3))
        XCTAssertEqual(binding.value(for: 2, count: 3), 2)
    }

    func testLampThreshold() {
        let lamp = Lamp(text: "FAULT", color: "amber", dataref: "d", index: nil, onValue: nil, bit: nil, invert: nil)
        XCTAssertTrue(lamp.isLit(.number(1)))
        XCTAssertFalse(lamp.isLit(.number(0)))
        XCTAssertFalse(lamp.isLit(nil))
        let exact = Lamp(text: "AVAIL", color: "green", dataref: "d", index: nil, onValue: 2, bit: nil, invert: nil)
        XCTAssertTrue(exact.isLit(.number(2)))
        XCTAssertFalse(exact.isLit(.number(1)))
    }
}

final class PanelMappingExtrasTests: XCTestCase {
    func testAliasesWinOverNearest() {
        // EXT PWR: 0 = off, 1 = on, 2 = available (switch off)
        let binding = ValueBinding(dataref: "x", index: 0, values: [0, 1], aliases: ["2": 0])
        XCTAssertEqual(binding.position(for: .number(2), count: 2), 0)
        XCTAssertEqual(binding.position(for: .number(1), count: 2), 1)
    }

    func testBitAndInvertLamps() {
        let on = Lamp(text: "ON", color: "blue", dataref: "d", index: nil, onValue: nil, bit: 1, invert: nil)
        let fault = Lamp(text: "FAULT", color: "amber", dataref: "d", index: nil, onValue: nil, bit: 2, invert: nil)
        let off = Lamp(text: "OFF", color: "white", dataref: "d", index: nil, onValue: nil, bit: 1, invert: true)
        XCTAssertTrue(on.isLit(.number(3)))
        XCTAssertTrue(fault.isLit(.number(2)))
        XCTAssertFalse(fault.isLit(.number(1)))
        XCTAssertTrue(off.isLit(.number(0)))
        XCTAssertFalse(off.isLit(.number(1)))
    }

    func testLayoutDecodes() throws {
        let json = """
        {"groups":[{"id":"overhead","title":"Overhead","icon":"square.grid.3x3"}],
         "phases":[{"id":"cold","title":"Cold & Dark","icon":"snowflake","subpanels":["elec","apu"]}]}
        """
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.groups.first?.id, "overhead")
        XCTAssertEqual(layout.phases.first?.subpanels, ["elec", "apu"])
    }
}

final class XPValueTextTests: XCTestCase {
    func testDecodesBase64PlainAndBytes() {
        XCTAssertEqual(XPValue.string(Data("122.800\0xx".utf8).base64EncodedString()).textValue, "122.800")
        XCTAssertEqual(XPValue.string("2000 ").textValue, "2000 ")   // not base64 (space) → plain
        XCTAssertEqual(XPValue.array([.number(55), .number(55), .number(0)]).textValue, "77")
        XCTAssertNil(XPValue.number(3).textValue)
    }
}
