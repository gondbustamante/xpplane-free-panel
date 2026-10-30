import Foundation

// Guided exercises over the procedures, read from `mapping/exercises/*.json`. An exercise runs
// one or more flows against the clock and scores how they were flown:
//
//   time          against the exercise's target
//   order         a sensed step done while an earlier sensed step is still pending
//   wrong control a switch moved by the user that the exercise does not use
//   undone        a step that was done and the user moved out of place again
//   hints         "show on panel", "set", a hint in exam mode, or ticking by hand a sensed step
//                 the simulator reads as not done
//
// A sensed step only counts once its controls have stayed put for `settle` seconds: a selector
// that has to pass through NORM on its way from CRANK to IGN/START does not tick (or untick) the
// steps that want NORM on the way.
//
// Each exercise declares the state it starts from (`coldAndDark`, `setup`), so the app can put
// the aircraft there first and the run does not begin with someone else's mistakes.
//
// Guided mode runs every step with the checklist on screen; exam mode hides it and only counts
// the sensed steps, the ones the app can judge.

public struct ExerciseBook: Codable, Sendable {
    public let id: String
    public let title: String
    public let exercises: [ExerciseDefinition]
}

public struct ExerciseDefinition: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// What the exercise trains, one or two lines.
    public let summary: String?
    /// "Básico", "Intermedio", "Avanzado".
    public let level: String?
    /// Procedure ids, in the order they are flown.
    public let procedures: [String]
    /// Time a trained pilot needs, in seconds.
    public let targetSeconds: Int
    /// State the aircraft should be in at the start.
    public let start: String?
    /// Starts from a cold and dark aircraft (the demo can reset it).
    public let coldAndDark: Bool?
    /// Procedures whose sensed items set the starting state, applied in order before the run.
    public let setup: [String]?

    public init(id: String, title: String, summary: String? = nil, level: String? = nil, procedures: [String],
                targetSeconds: Int, start: String? = nil, coldAndDark: Bool? = nil, setup: [String]? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.level = level
        self.procedures = procedures
        self.targetSeconds = targetSeconds
        self.start = start
        self.coldAndDark = coldAndDark
        self.setup = setup
    }

    public var startsColdAndDark: Bool { coldAndDark ?? false }
    /// Has a starting state the app can prepare.
    public var hasStartingState: Bool { startsColdAndDark || !(setup ?? []).isEmpty }
}

public enum ExerciseMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case guided
    case exam

    public var id: String { rawValue }
}

public struct ExerciseStep: Sendable, Hashable {
    public let procedureID: String
    /// Index of the item in its procedure.
    public let index: Int
    public let item: ProcedureItem

    public var controls: Set<String> { Set((item.checks ?? []).map(\.control)) }
}

public struct ExerciseMistake: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case wrongControl
        case undone
        case outOfOrder
    }

    public let kind: Kind
    /// Control involved (wrong control), or the step's first control.
    public let control: String?
    /// Step text, "CHALLENGE ... RESPONSE".
    public let step: String?
    /// Seconds into the run.
    public let at: Double
}

public struct ExerciseResult: Codable, Sendable, Hashable {
    public let exerciseID: String
    public let mode: ExerciseMode
    public let date: Date
    public let elapsed: Double
    public let target: Double
    public let steps: Int
    public let mistakes: [ExerciseMistake]
    public let hints: Int

    public var score: Int { ExerciseScoring.score(elapsed: elapsed, target: target, mistakes: mistakes, hints: hints) }
    public var stars: Int { ExerciseScoring.stars(score: score) }

    public func count(_ kind: ExerciseMistake.Kind) -> Int {
        mistakes.filter { $0.kind == kind }.count
    }
}

public enum ExerciseScoring {
    public static let undonePenalty = 5
    public static let outOfOrderPenalty = 3
    public static let wrongControlPenalty = 2
    public static let hintPenalty = 5
    /// At most this much is lost to time.
    public static let maxTimePenalty = 30

    /// Points lost to time: half a point per percent over the target, up to `maxTimePenalty`.
    public static func timePenalty(elapsed: Double, target: Double) -> Int {
        guard target > 0, elapsed > target else { return 0 }
        return min(maxTimePenalty, Int(((elapsed / target - 1) * 50).rounded(.down)))
    }

    /// 0…100.
    public static func score(elapsed: Double, target: Double, mistakes: [ExerciseMistake], hints: Int) -> Int {
        var score = 100 - timePenalty(elapsed: elapsed, target: target) - hints * hintPenalty
        for mistake in mistakes {
            switch mistake.kind {
            case .undone: score -= undonePenalty
            case .outOfOrder: score -= outOfOrderPenalty
            case .wrongControl: score -= wrongControlPenalty
            }
        }
        return max(0, score)
    }

    public static func stars(score: Int) -> Int {
        switch score {
        case 90...: return 3
        case 75..<90: return 2
        case 50..<75: return 1
        default: return 0
        }
    }
}

/// Follows one run of an exercise. Feed it the control positions after every change and the
/// user's own touches; it keeps which steps are done and the mistakes made.
public struct ExerciseTracker: Sendable {
    public let definition: ExerciseDefinition
    public let mode: ExerciseMode
    public let steps: [ExerciseStep]
    public private(set) var mistakes: [ExerciseMistake] = []
    public private(set) var hints = 0
    /// Steps already done when the run started: they score nothing either way.
    public private(set) var doneAtStart: Set<Int> = []
    private(set) var done: Set<Int> = []
    /// Sensed steps ticked by hand while the simulator read them as not done (counted as hints).
    private var forced: Set<Int> = []
    /// Steps with a later step on one of their controls: once done they stay done, since the
    /// later step is expected to move the control again (ENG MODE IGN/START, then NORM).
    private let superseded: Set<Int>
    private let relevant: Set<String>
    private var started = false
    /// Seconds a control must hold a position before the step counts it.
    public let settle: Double
    /// Last sensed state of each step and since when it holds.
    private var lastStates: [ProcedureCheckState] = []
    private var since: [Double] = []
    /// When each step was reached, for the finishing time.
    private var reachedAt: [Int: Double] = [:]

    /// Steps from `procedures` (looked up by id): optional items are left out, and so are items
    /// that repeat an earlier step's checks (FUEL PUMPS ON in two flows). In exam mode only
    /// sensed items count.
    public init(definition: ExerciseDefinition, procedures: [Procedure], mode: ExerciseMode, settle: Double = 2) {
        self.definition = definition
        self.mode = mode
        self.settle = settle
        var steps: [ExerciseStep] = []
        var seenChecks: Set<[ProcedureCheck]> = []
        for id in definition.procedures {
            guard let procedure = procedures.first(where: { $0.id == id }) else { continue }
            for (index, item) in procedure.items.enumerated() where !item.isOptional {
                if mode == .exam && !item.isSensed { continue }
                if let checks = item.checks, !checks.isEmpty {
                    if seenChecks.contains(checks) { continue }
                    seenChecks.insert(checks)
                }
                steps.append(ExerciseStep(procedureID: procedure.id, index: index, item: item))
            }
        }
        self.steps = steps
        relevant = steps.reduce(into: Set<String>()) { $0.formUnion($1.controls) }
        var superseded: Set<Int> = []
        for (i, step) in steps.enumerated() where !step.controls.isEmpty {
            if steps[(i + 1)...].contains(where: { !$0.controls.isDisjoint(with: step.controls) }) {
                superseded.insert(i)
            }
        }
        self.superseded = superseded
    }

    public var isComplete: Bool { !steps.isEmpty && done.count == steps.count }
    public var doneCount: Int { done.count }

    public func isDone(_ step: Int) -> Bool { done.contains(step) }

    /// First step still to do.
    public var currentStep: Int? { steps.indices.first { !done.contains($0) } }

    /// The user moved or pressed a control. Controls the exercise does not use count as mistakes.
    public mutating func touch(control id: String, at time: Double) {
        guard started, !isComplete, !relevant.contains(id) else { return }
        mistakes.append(ExerciseMistake(kind: .wrongControl, control: id, step: nil, at: time))
    }

    public mutating func useHint() {
        guard started, !isComplete else { return }
        hints += 1
    }

    /// Re-reads every step. `position` gives a control's position name (nil when unknown),
    /// `ticked` whether the user ticked the step by hand. The first call records the starting
    /// state without scoring it.
    public mutating func update(at time: Double, position: (String) -> String?, ticked: (ExerciseStep) -> Bool) {
        let states = steps.map { $0.item.sensedState(position: position) }
        let manual = steps.map(ticked)

        guard started else {
            started = true
            lastStates = states
            since = steps.map { _ in time }
            doneAtStart = Set(steps.indices.filter { states[$0] == .satisfied || manual[$0] })
            done = doneAtStart
            return
        }
        for i in steps.indices where states[i] != lastStates[i] {
            lastStates[i] = states[i]
            since[i] = time
        }
        func settled(_ i: Int) -> Bool { time - since[i] >= settle }
        func isDoneNow(_ i: Int) -> Bool { manual[i] || (states[i] == .satisfied && settled(i)) }

        for i in steps.indices {
            let step = steps[i]
            if step.item.isSensed, manual[i], states[i] == .unsatisfied, !forced.contains(i) {
                forced.insert(i)
                hints += 1
            }
            if isDoneNow(i), !done.contains(i) {
                // Skipped: an earlier sensed step not done and not even reached right now.
                let skipped = steps.indices.contains { j in
                    j < i && steps[j].item.isSensed && !done.contains(j) && states[j] != .satisfied
                }
                if step.item.isSensed, states[i] == .satisfied, skipped {
                    mistakes.append(mistake(.outOfOrder, step, at: since[i]))
                }
                done.insert(i)
                reachedAt[i] = manual[i] ? time : since[i]
            } else if done.contains(i), !manual[i], states[i] != .satisfied, settled(i), !superseded.contains(i) {
                done.remove(i)
                reachedAt[i] = nil
                // Moving the control to what another step wants is the procedure, not a mistake
                // (MODE NORM in place at the start, then IGN/START for the engine start).
                let wantedElsewhere = steps.indices.contains { k in
                    k != i && states[k] == .satisfied && !steps[k].controls.isDisjoint(with: step.controls)
                }
                if step.item.isSensed, !forced.contains(i), !wantedElsewhere {
                    mistakes.append(mistake(.undone, step, at: since[i]))
                }
            }
        }
    }

    /// Seconds into the run when the last step was reached, once all are done.
    public var finishedAt: Double? {
        guard isComplete else { return nil }
        return reachedAt.values.max() ?? 0
    }

    public func result(elapsed: Double, date: Date = Date()) -> ExerciseResult {
        ExerciseResult(exerciseID: definition.id, mode: mode, date: date, elapsed: elapsed,
                       target: Double(definition.targetSeconds), steps: steps.count,
                       mistakes: mistakes, hints: hints)
    }

    private func mistake(_ kind: ExerciseMistake.Kind, _ step: ExerciseStep, at time: Double) -> ExerciseMistake {
        ExerciseMistake(kind: kind, control: step.item.checks?.first?.control,
                        step: "\(step.item.challenge) … \(step.item.response)", at: time)
    }
}

public enum ExerciseLoader {
    /// Every `*.json` in `directory`, books in file-name order.
    public static func loadAll(in directory: URL) throws -> [ExerciseDefinition] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { try JSONDecoder().decode(ExerciseBook.self, from: Data(contentsOf: $0)).exercises }
    }
}
