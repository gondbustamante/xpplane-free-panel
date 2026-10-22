import Foundation

/// Metadata for a dataref as listed by `GET /api/v2/datarefs`.
public struct DatarefInfo: Decodable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let valueType: String
    public let isWritable: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case valueType = "value_type"
        case isWritable = "is_writable"
    }
}

/// Metadata for a command as listed by `GET /api/v2/commands`.
public struct CommandInfo: Decodable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
}

struct ListEnvelope<T: Decodable>: Decodable {
    let data: [T]
}

struct ValueEnvelope: Decodable {
    let data: XPValue
}

/// A dataref name plus an optional array index, e.g. `AirbusFBW/OHPLightSwitches[7]`.
public struct DatarefKey: Hashable, Sendable, CustomStringConvertible {
    public let name: String
    public let index: Int?

    public init(_ name: String, index: Int? = nil) {
        self.name = name
        self.index = index
    }

    public var description: String {
        if let index { return "\(name)[\(index)]" }
        return name
    }
}

public enum XPlaneError: Error, LocalizedError, Sendable {
    case invalidURL
    case notConnected
    case http(status: Int, body: String)
    case notFound(String)
    case webSocket(code: String, message: String?)
    case decoding(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Dirección de X-Plane no válida."
        case .notConnected: return "No hay conexión con X-Plane."
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(200))"
        case .notFound(let name): return "X-Plane no conoce '\(name)'. ¿Está cargado el ToLiss?"
        case .webSocket(let code, let message): return "WebSocket \(code): \(message ?? "")"
        case .decoding(let detail): return "Respuesta inesperada: \(detail)"
        case .timeout: return "X-Plane no respondió a tiempo."
        }
    }
}
