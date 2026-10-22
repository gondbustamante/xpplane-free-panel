import Foundation

/// Request/response and streaming layer over `URLSessionWebSocketTask`.
/// Correlates `result` messages with their `req_id`; forwards everything else to `incoming`.
actor WebSocketClient {
    typealias IncomingHandler = @Sendable (WSIncoming) -> Void
    typealias CloseHandler = @Sendable (Error?) -> Void

    private let url: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private var task: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<WSResult, Error>] = [:]
    private var onIncoming: IncomingHandler?
    private var onClose: CloseHandler?

    init(url: URL, session: URLSession) {
        self.url = url
        self.session = session
    }

    func setHandlers(incoming: @escaping IncomingHandler, close: @escaping CloseHandler) {
        onIncoming = incoming
        onClose = close
    }

    func connect() {
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receiver = Task { [weak self] in
            await self?.receiveLoop(on: socket)
        }
    }

    func disconnect() {
        receiver?.cancel()
        receiver = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        failAll(XPlaneError.notConnected)
    }

    /// Sends a request and waits for the matching `result` message (5 s timeout).
    func send<P: Encodable & Sendable>(type: String, params: P) async throws -> WSResult {
        guard let socket = task else { throw XPlaneError.notConnected }
        let requestID = nextRequestID
        nextRequestID += 1
        let payload = try encoder.encode(WSRequest(req_id: requestID, type: type, params: params))
        let text = String(decoding: payload, as: UTF8.self)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WSResult, Error>) in
            pending[requestID] = continuation
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    self.fail(requestID, with: error)
                    return
                }
                try? await Task.sleep(for: .seconds(5))
                self.fail(requestID, with: XPlaneError.timeout)
            }
        }
    }

    // MARK: Private

    private func fail(_ requestID: Int, with error: Error) {
        pending.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: error)
        }
    }

    private func receiveLoop(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(text)
                case .data(let data):
                    handle(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled { closed(with: error) }
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let incoming = try? WSIncoming.decode(text) else { return }
        if case .result(let result) = incoming,
           let continuation = pending.removeValue(forKey: result.reqID) {
            continuation.resume(returning: result)
            return
        }
        onIncoming?(incoming)
    }

    private func closed(with error: Error?) {
        task = nil
        failAll(error ?? XPlaneError.notConnected)
        onClose?(error)
    }
}
