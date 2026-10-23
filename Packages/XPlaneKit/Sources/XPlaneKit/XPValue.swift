import Foundation

/// A JSON value as exchanged with the X-Plane Web API.
/// Dataref values arrive as numbers, arrays of numbers, or (for `data` datarefs) strings.
public enum XPValue: Codable, Equatable, Sendable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case array([XPValue])
    case null

    public init(_ double: Double) { self = .number(double) }
    public init(_ int: Int) { self = .number(Double(int)) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let number = try? container.decode(Double.self) { self = .number(number); return }
        if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        if let array = try? container.decode([XPValue].self) { self = .array(array); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let double):
            // X-Plane rejects "1.0" for int datarefs; emit integral numbers without decimals.
            if double.rounded() == double, abs(double) < 1e15 {
                try container.encode(Int64(double))
            } else {
                try container.encode(double)
            }
        case .bool(let bool): try container.encode(bool)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .null: try container.encodeNil()
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let double): return double
        case .bool(let bool): return bool ? 1 : 0
        case .string(let string): return Double(string)
        case .array, .null: return nil
        }
    }

    public var intValue: Int? {
        guard let double = doubleValue, double.isFinite else { return nil }
        return Int(double.rounded())
    }

    /// Text of a `data` dataref: the Web API sends base64; plain strings and byte arrays are
    /// accepted too. Stops at the first NUL.
    public var textValue: String? {
        let bytes: [UInt8]
        switch self {
        case .string(let text):
            if !text.isEmpty, let data = Data(base64Encoded: text) {
                bytes = [UInt8](data)
            } else {
                return text
            }
        case .array(let elements):
            bytes = elements.compactMap { $0.intValue }.map { UInt8(clamping: $0) }
        default:
            return nil
        }
        let visible = bytes.prefix { $0 != 0 }
        return String(decoding: visible, as: UTF8.self)
    }

    public var arrayValue: [XPValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// The element at `index` for array values, or the value itself when `index` is nil.
    public func element(at index: Int?) -> XPValue? {
        guard let index else { return self }
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
