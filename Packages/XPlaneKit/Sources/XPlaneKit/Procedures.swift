import Foundation

// Normal procedures (flows) and checklists, read from `mapping/procedures/*.json`.
//
//   flow       what to do, in panel-scan order ("ADIRS 1, 2, 3 ... NAV")
//   checklist  the read-and-confirm list that follows the flow (Airbus normal checklist)
//
// An item with `checks` is sensed: it ticks itself when every named control reads one of its
// expected positions (position names as in the control's `positions`). Items without checks,
// and sensed items the simulator cannot confirm yet, are ticked by hand.

public struct ProcedureBook: Codable, Sendable {
    public let id: String
    public let title: String
    public let procedures: [Procedure]
}

public struct Procedure: Codable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case flow
        case checklist
    }

    public let id: String
    public let kind: Kind
    public let title: String
    /// Flight phase id from `layout.json`.
    public let phase: String?
    /// One line shown under the title.
    public let summary: String?
    public let items: [ProcedureItem]

    /// Subpanel ids involved, in item order without repeats: explicit `panels` first, then the
    /// panel of each sensed control. `panelOfControl` maps a control id to its subpanel id.
    public func panels(panelOfControl: (String) -> String?) -> [String] {
        var result: [String] = []
        for item in items {
            for id in item.panels ?? [] where !result.contains(id) { result.append(id) }
            for check in item.checks ?? [] {
                if let id = panelOfControl(check.control), !result.contains(id) { result.append(id) }
            }
        }
        return result
    }
}

public struct ProcedureItem: Codable, Sendable, Hashable {
    /// Left column, as printed on the checklist ("ADIRS").
    public let challenge: String
    /// Right column ("NAV", "___ SET (BOTH)").
    public let response: String
    /// Explanation shown under the line.
    public let note: String?
    /// Why the step is done: the reasoning behind it, shown on demand.
    public let why: String?
    /// Sub-lines (ECAM memo items).
    public let sub: [String]?
    /// Both pilots answer.
    public let both: Bool?
    /// Done only when it applies ("EXT PWR ... ON" when a GPU is connected).
    public let optional: Bool?
    /// Panels to show for this item besides the sensed controls' own (MCDU, FCU…).
    public let panels: [String]?
    public let checks: [ProcedureCheck]?

    public var isSensed: Bool { !(checks ?? []).isEmpty }
    public var isOptional: Bool { optional ?? false }

    /// Sensed state from the current position name of each control (nil when unknown).
    public func sensedState(position: (String) -> String?) -> ProcedureCheckState {
        guard let checks, !checks.isEmpty else { return .notSensed }
        var known = true
        for check in checks {
            guard let current = position(check.control) else {
                known = false
                continue
            }
            if !check.expect.contains(current) { return .unsatisfied }
        }
        return known ? .satisfied : .unknown
    }
}

public struct ProcedureCheck: Codable, Sendable, Hashable {
    public let control: String
    /// Any of these positions satisfies the item.
    public let expect: [String]
}

public enum ProcedureCheckState: Sendable, Equatable {
    /// The item has no checks.
    case notSensed
    /// Not every control has reported its position yet.
    case unknown
    case satisfied
    case unsatisfied
}

public enum ProcedureLoader {
    /// Every `*.json` in `directory`, books in file-name order, procedures in file order.
    public static func loadAll(in directory: URL) throws -> [Procedure] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { try JSONDecoder().decode(ProcedureBook.self, from: Data(contentsOf: $0)).procedures }
    }
}
