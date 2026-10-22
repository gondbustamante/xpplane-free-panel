import Foundation

public struct DatarefUpdate: Sendable {
    public let name: String
    public let value: XPValue
}

/// Facade over the X-Plane 12 Web API (12.1.4+, `/api/v2`).
///
/// Design notes:
/// - Array datarefs are subscribed whole (no `index`) so one update carries every element and
///   several controls can share a single subscription (e.g. `AirbusFBW/OHPLightSwitches`).
/// - Writes and one-shot commands go through REST; subscriptions and held commands go through
///   the WebSocket.
/// - `updates` and `stateChanges` are single-consumer streams: one view model should own them.
public actor XPlaneClient {
    public enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    public let host: String
    public let port: Int
    public private(set) var state: State = .disconnected
    public nonisolated let updates: AsyncStream<DatarefUpdate>
    public nonisolated let stateChanges: AsyncStream<State>

    private let updatesContinuation: AsyncStream<DatarefUpdate>.Continuation
    private let stateContinuation: AsyncStream<State>.Continuation
    private let session: URLSession
    private let rest: RESTClient
    private let webSocketURL: URL
    private var socket: WebSocketClient?
    private var datarefCache: [String: DatarefInfo] = [:]
    private var commandCache: [String: CommandInfo] = [:]
    private var subscribedNames: [Int64: String] = [:]
    private var latest: [String: XPValue] = [:]

    public init(host: String, port: Int = 8086) {
        self.host = host
        self.port = port

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        self.session = session

        let fallback = URL(string: "http://127.0.0.1:8086/api/v2")!
        let restURL = URL(string: "http://\(host):\(port)/api/v2") ?? fallback
        self.rest = RESTClient(baseURL: restURL, session: session)
        self.webSocketURL = URL(string: "ws://\(host):\(port)/api/v2") ?? URL(string: "ws://127.0.0.1:8086/api/v2")!

        let (updates, updatesContinuation) = AsyncStream.makeStream(of: DatarefUpdate.self, bufferingPolicy: .bufferingNewest(512))
        self.updates = updates
        self.updatesContinuation = updatesContinuation
        let (states, stateContinuation) = AsyncStream.makeStream(of: State.self, bufferingPolicy: .bufferingNewest(16))
        self.stateChanges = states
        self.stateContinuation = stateContinuation
    }

    // MARK: Connection

    public func connect() async throws {
        if case .connected = state { return }
        setState(.connecting)
        do {
            // REST probe first: a clear error if the host/port/relay is wrong.
            _ = try await rest.datarefs(named: "sim/time/total_running_time_sec")

            let socket = WebSocketClient(url: webSocketURL, session: session)
            await socket.setHandlers(
                incoming: { [weak self] incoming in
                    Task { await self?.handle(incoming) }
                },
                close: { [weak self] error in
                    Task { await self?.socketClosed(error) }
                }
            )
            await socket.connect()
            self.socket = socket
            setState(.connected)

            // Re-subscribe after a reconnect.
            let previous = Array(Set(subscribedNames.values))
            subscribedNames.removeAll()
            if !previous.isEmpty {
                _ = try await subscribe(datarefs: previous)
            }
        } catch {
            setState(.failed(describe(error)))
            throw error
        }
    }

    public func disconnect() async {
        await socket?.disconnect()
        socket = nil
        setState(.disconnected)
    }

    // MARK: Datarefs

    public func dataref(named name: String) async throws -> DatarefInfo {
        if let cached = datarefCache[name] { return cached }
        guard let info = try await rest.datarefs(named: name).first(where: { $0.name == name }) else {
            throw XPlaneError.notFound(name)
        }
        datarefCache[name] = info
        return info
    }

    /// Subscribes to value updates. Returns the names X-Plane does not know (e.g. aircraft not
    /// loaded) instead of failing the whole batch; transport errors still throw.
    @discardableResult
    public func subscribe(datarefs names: [String]) async throws -> [String] {
        guard let socket else { throw XPlaneError.notConnected }
        var refs: [WSDatarefRef] = []
        var unresolved: [String] = []
        for name in names where !subscribedNames.values.contains(name) {
            do {
                let info = try await dataref(named: name)
                subscribedNames[info.id] = name
                refs.append(WSDatarefRef(id: info.id, index: nil))
            } catch XPlaneError.notFound {
                unresolved.append(name)
            }
        }
        guard !refs.isEmpty else { return unresolved }
        let result = try await socket.send(type: "dataref_subscribe_values", params: WSSubscribeParams(datarefs: refs))
        guard result.success else {
            throw XPlaneError.webSocket(code: result.errorCode ?? "error", message: result.errorMessage)
        }
        return unresolved
    }

    /// Last value received through the subscription, if any.
    public func cachedValue(of key: DatarefKey) -> XPValue? {
        latest[key.name]?.element(at: key.index)
    }

    public func read(_ key: DatarefKey) async throws -> XPValue {
        let info = try await dataref(named: key.name)
        return try await rest.value(datarefID: info.id, index: key.index)
    }

    public func write(_ key: DatarefKey, _ value: XPValue) async throws {
        let info = try await dataref(named: key.name)
        try await rest.setValue(datarefID: info.id, index: key.index, value: value)
    }

    public func searchDatarefs(containing fragment: String) async throws -> [DatarefInfo] {
        try await rest.allDatarefs().filter { $0.name.localizedCaseInsensitiveContains(fragment) }
    }

    // MARK: Commands

    public func command(named name: String) async throws -> CommandInfo {
        if let cached = commandCache[name] { return cached }
        guard let info = try await rest.commands(named: name).first(where: { $0.name == name }) else {
            throw XPlaneError.notFound(name)
        }
        commandCache[name] = info
        return info
    }

    /// Press-and-release (`duration` 0) or hold for `duration` seconds, then release.
    public func fire(command name: String, duration: Double = 0) async throws {
        let info = try await command(named: name)
        try await rest.activate(commandID: info.id, duration: duration)
    }

    /// Begin (`active: true`) or end (`active: false`) a command, for controls held down.
    public func hold(command name: String, active: Bool) async throws {
        guard let socket else { throw XPlaneError.notConnected }
        let info = try await command(named: name)
        let params = WSCommandParams(commands: [WSCommandActive(id: info.id, is_active: active, duration: nil)])
        let result = try await socket.send(type: "command_set_is_active", params: params)
        guard result.success else {
            throw XPlaneError.webSocket(code: result.errorCode ?? "error", message: result.errorMessage)
        }
    }

    public func searchCommands(containing fragment: String) async throws -> [CommandInfo] {
        try await rest.allCommands().filter { $0.name.localizedCaseInsensitiveContains(fragment) }
    }

    // MARK: Private

    private func setState(_ newState: State) {
        state = newState
        stateContinuation.yield(newState)
    }

    private func handle(_ incoming: WSIncoming) {
        guard case .datarefUpdate(let values) = incoming else { return }
        for (id, value) in values {
            guard let name = subscribedNames[id] else { continue }
            latest[name] = value
            updatesContinuation.yield(DatarefUpdate(name: name, value: value))
        }
    }

    private func socketClosed(_ error: Error?) {
        socket = nil
        if case .disconnected = state { return }
        setState(.failed(error.map(describe) ?? "X-Plane cerró la conexión."))
    }

    private func describe(_ error: Error) -> String {
        if let xp = error as? XPlaneError, let text = xp.errorDescription { return text }
        return error.localizedDescription
    }
}
