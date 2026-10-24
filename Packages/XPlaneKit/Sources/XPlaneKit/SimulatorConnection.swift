import Foundation

/// What the panel talks to: the X-Plane Web API (`XPlaneClient`) or the offline
/// `DemoSimulator`. Both publish dataref values through `updates` and accept the same writes and
/// commands, so the UI does not know which one is behind it.
public protocol SimulatorConnection: Actor {
    nonisolated var updates: AsyncStream<DatarefUpdate> { get }
    nonisolated var stateChanges: AsyncStream<XPlaneClient.State> { get }

    func connect() async throws
    func disconnect() async

    /// Subscribes to value updates and returns the names the simulator does not know.
    @discardableResult
    func subscribe(datarefs names: [String]) async throws -> [String]
    func write(_ key: DatarefKey, _ value: XPValue) async throws
    /// Press-and-release (`duration` 0) or hold for `duration` seconds, then release.
    func fire(command name: String, duration: Double) async throws
}

public extension SimulatorConnection {
    func fire(command name: String) async throws {
        try await fire(command: name, duration: 0)
    }
}

extension XPlaneClient: SimulatorConnection {}
