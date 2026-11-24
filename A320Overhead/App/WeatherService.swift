import Foundation
import XPlaneKit

/// Live weather from aviationweather.gov (NOAA's Aviation Weather Center): free, no key. METARs
/// and TAFs are read as raw text, the stable format; SIGMETs as JSON.
enum WeatherService {
    private static let base = "https://aviationweather.gov/api/data/"

    struct Result {
        var metars: [String: METARReport] = [:]
        var tafs: [String: TAFReport] = [:]
        var sigmets: [Sigmet] = []
    }

    static func fetch(airports: [String], now: Date = Date()) async throws -> Result {
        let ids = airports.joined(separator: ",")
        async let metarText = text("metar?ids=\(ids)&format=raw")
        async let tafText = text("taf?ids=\(ids)&format=raw")
        async let sigmetData = data("isigmet?format=json")
        var result = Result()
        for line in try await metarText.split(whereSeparator: \.isNewline) {
            if let report = METARReport.decode(String(line)) { result.metars[report.station] = report }
        }
        for raw in splitTAFs(try await tafText, stations: Set(airports)) {
            if let report = TAFReport.decode(raw, reference: now) { result.tafs[report.station] = report }
        }
        // SIGMETs are a bonus: the airports' weather is still worth showing without them.
        result.sigmets = (try? await sigmetData).map(Sigmet.decode(json:)) ?? []
        return result
    }

    /// The raw TAF feed puts one TAF over several lines: a new one starts at "TAF" or at a
    /// requested station followed by its issue time.
    static func splitTAFs(_ text: String, stations: Set<String>) -> [String] {
        var tafs: [String] = []
        var current: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let tokens = line.split(separator: " ").map(String.init)
            guard let first = tokens.first else { continue }
            let starts = first == "TAF" || (stations.contains(first) && tokens.count > 1 && tokens[1].hasSuffix("Z"))
            if starts, !current.isEmpty {
                tafs.append(current.joined(separator: " "))
                current = []
            }
            current.append(line.trimmingCharacters(in: .whitespaces))
        }
        if !current.isEmpty { tafs.append(current.joined(separator: " ")) }
        return tafs
    }

    private static func data(_ path: String) async throws -> Data {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("A320Overhead", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), http.statusCode != 204 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func text(_ path: String) async throws -> String {
        String(decoding: try await data(path), as: UTF8.self)
    }
}
