import Foundation

/// Thin wrapper over the REST half of the X-Plane Web API (`http://host:8086/api/v2`).
/// Used to resolve names to ids, read/write single values and fire one-shot commands.
struct RESTClient: Sendable {
    let baseURL: URL
    let session: URLSession

    // MARK: Datarefs

    func datarefs(named name: String) async throws -> [DatarefInfo] {
        let data = try await request("GET", "datarefs", query: [URLQueryItem(name: "filter[name]", value: name)])
        return try decode(ListEnvelope<DatarefInfo>.self, from: data).data
    }

    func allDatarefs() async throws -> [DatarefInfo] {
        let data = try await request("GET", "datarefs")
        return try decode(ListEnvelope<DatarefInfo>.self, from: data).data
    }

    func value(datarefID: Int64, index: Int?) async throws -> XPValue {
        var query: [URLQueryItem] = []
        if let index { query.append(URLQueryItem(name: "index", value: String(index))) }
        let data = try await request("GET", "datarefs/\(datarefID)/value", query: query)
        return try decode(ValueEnvelope.self, from: data).data
    }

    func setValue(datarefID: Int64, index: Int?, value: XPValue) async throws {
        struct Body: Encodable { let data: XPValue }
        var query: [URLQueryItem] = []
        if let index { query.append(URLQueryItem(name: "index", value: String(index))) }
        let body = try JSONEncoder().encode(Body(data: value))
        _ = try await request("PATCH", "datarefs/\(datarefID)/value", query: query, body: body)
    }

    // MARK: Commands

    func commands(named name: String) async throws -> [CommandInfo] {
        let data = try await request("GET", "commands", query: [URLQueryItem(name: "filter[name]", value: name)])
        return try decode(ListEnvelope<CommandInfo>.self, from: data).data
    }

    func allCommands() async throws -> [CommandInfo] {
        let data = try await request("GET", "commands")
        return try decode(ListEnvelope<CommandInfo>.self, from: data).data
    }

    /// One-shot activation. `duration` 0 presses and releases immediately (max 10 s).
    func activate(commandID: Int64, duration: Double) async throws {
        struct Body: Encodable { let duration: Double }
        let body = try JSONEncoder().encode(Body(duration: duration))
        _ = try await request("POST", "command/\(commandID)/activate", body: body)
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw XPlaneError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw XPlaneError.invalidURL }

        var urlRequest = URLRequest(url: url, timeoutInterval: 8)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw XPlaneError.http(status: -1, body: "sin respuesta HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw XPlaneError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XPlaneError.decoding(String(describing: error))
        }
    }
}
