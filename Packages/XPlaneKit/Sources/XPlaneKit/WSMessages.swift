import Foundation

// Wire format of the X-Plane Web API WebSocket channel (`ws://host:8086/api/v2`).
// Every request is `{"req_id": n, "type": "...", "params": {...}}` and is answered by a
// `{"type": "result", "req_id": n, "success": bool, ...}` message. Subscriptions then stream
// `{"type": "dataref_update_values", "data": {"<id>": value, ...}}` messages.

struct WSRequest<P: Encodable & Sendable>: Encodable, Sendable {
    let req_id: Int
    let type: String
    let params: P
}

struct WSDatarefRef: Encodable, Sendable {
    let id: Int64
    let index: Int?
}

struct WSSubscribeParams: Encodable, Sendable {
    let datarefs: [WSDatarefRef]
}

struct WSDatarefSet: Encodable, Sendable {
    let id: Int64
    let value: XPValue
    let index: Int?
}

struct WSSetValuesParams: Encodable, Sendable {
    let datarefs: [WSDatarefSet]
}

struct WSCommandActive: Encodable, Sendable {
    let id: Int64
    let is_active: Bool
    let duration: Double?
}

struct WSCommandParams: Encodable, Sendable {
    let commands: [WSCommandActive]
}

public struct WSResult: Decodable, Sendable {
    public let reqID: Int
    public let success: Bool
    public let errorCode: String?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case reqID = "req_id"
        case success
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

enum WSIncoming: Sendable {
    case result(WSResult)
    case datarefUpdate([Int64: XPValue])
    case commandUpdate([Int64: Bool])
    case unknown(String)

    static func decode(_ text: String) throws -> WSIncoming {
        struct Header: Decodable { let type: String }
        struct DatarefUpdate: Decodable { let data: [String: XPValue] }
        struct CommandUpdate: Decodable { let data: [String: Bool] }

        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        switch header.type {
        case "result":
            return .result(try decoder.decode(WSResult.self, from: data))
        case "dataref_update_values":
            let update = try decoder.decode(DatarefUpdate.self, from: data)
            var byID: [Int64: XPValue] = [:]
            for (key, value) in update.data {
                if let id = Int64(key) { byID[id] = value }
            }
            return .datarefUpdate(byID)
        case "command_update_is_active":
            let update = try decoder.decode(CommandUpdate.self, from: data)
            var byID: [Int64: Bool] = [:]
            for (key, value) in update.data {
                if let id = Int64(key) { byID[id] = value }
            }
            return .commandUpdate(byID)
        default:
            return .unknown(header.type)
        }
    }
}
