import Foundation
import XPlaneKit

/// What the list of reports shows, without loading each trace.
struct DebriefIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let end: Date
    let score: Int
    let events: Int

    init(_ debrief: FlightDebrief) {
        id = debrief.id
        title = debrief.title
        end = debrief.end
        score = debrief.score
        events = debrief.events.count
    }
}

/// Reports are a few hundred KB each: one JSON file per flight in Application Support, not
/// UserDefaults.
enum DebriefStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Debriefs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func url(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).json")
    }

    static func save(_ debrief: FlightDebrief) -> Bool {
        guard let url = url(debrief.id), let data = try? JSONEncoder().encode(debrief) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func load(_ id: UUID) -> FlightDebrief? {
        guard let url = url(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FlightDebrief.self, from: data)
    }

    static func delete(_ id: UUID) {
        guard let url = url(id) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
