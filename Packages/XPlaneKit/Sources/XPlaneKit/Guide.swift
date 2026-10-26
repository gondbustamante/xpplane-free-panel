import Foundation

// Teaching content for the learn mode, read from `mapping/guide/*.json`: what each system is
// for and what each control does, position by position. Kept apart from the panel mapping so
// the explanations can grow without touching the files that drive the simulator.
//
//   systems       one entry per system, tied to the subpanels that belong to it
//   explanations  one entry per control (or per group of identical controls: RMP 1 and 2,
//                 captain and F/O EFIS), keyed by control id. FCU ids come from
//                 `mapping/fcu/fcu.json`; MCDU keys use "mcdu.<command suffix>" ("mcdu.Init").

public struct GuideBook: Codable, Sendable {
    public let id: String
    public let title: String
    public let source: String?
    public let systems: [SystemGuide]?
    public let explanations: [ControlGuide]?
}

public struct SystemGuide: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// Subpanel ids (or "fcu", "mcdu") whose controls belong to this system.
    public let panels: [String]
    /// What the system does, in a few lines.
    public let summary: String
    /// Extra paragraphs: architecture, how it is fed, what to watch.
    public let details: [String]?
    /// ECAM system page that shows it ("ELEC", "HYD"…).
    public let ecam: String?
}

public struct ControlGuide: Codable, Sendable, Hashable {
    /// Control ids this explanation covers.
    public let controls: [String]
    /// Heading; defaults to the control's label.
    public let title: String?
    /// What it does.
    public let what: String
    /// Meaning of each position, keyed by position name as in the control's `positions`.
    public let positions: [String: String]?
    /// Normal operation: where it lives and when it is moved.
    public let normal: String?
    /// Pitfalls and things not to do.
    public let caution: String?
}

/// Every guide book merged, indexed for lookups by control and by panel.
public struct Guide: Sendable {
    public let systems: [SystemGuide]
    private let byControl: [String: ControlGuide]
    private let systemByPanel: [String: SystemGuide]

    public static let empty = Guide(books: [])

    public init(books: [GuideBook]) {
        var systems: [SystemGuide] = []
        var byControl: [String: ControlGuide] = [:]
        var systemByPanel: [String: SystemGuide] = [:]
        for book in books {
            for system in book.systems ?? [] {
                systems.append(system)
                for panel in system.panels where systemByPanel[panel] == nil {
                    systemByPanel[panel] = system
                }
            }
            for explanation in book.explanations ?? [] {
                for id in explanation.controls where byControl[id] == nil {
                    byControl[id] = explanation
                }
            }
        }
        self.systems = systems
        self.byControl = byControl
        self.systemByPanel = systemByPanel
    }

    public var isEmpty: Bool { byControl.isEmpty && systems.isEmpty }

    public func explanation(for control: String) -> ControlGuide? {
        byControl[control]
    }

    public func system(forPanel panel: String) -> SystemGuide? {
        systemByPanel[panel]
    }
}

public enum GuideLoader {
    /// Every `*.json` in `directory`, merged in file-name order (the first explanation of a
    /// control wins).
    public static func load(in directory: URL) throws -> Guide {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let books = try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(GuideBook.self, from: Data(contentsOf: $0)) }
        return Guide(books: books)
    }
}
