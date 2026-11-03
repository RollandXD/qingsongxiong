import AIUsageDomain
import Foundation
import Network

/// 只绑定 127.0.0.1 的单次回调接收器；不开放局域网端口、不记录回调 URL。
public actor LoopbackCallbackReceiver {
    private let callbackPath: String
    private let callbackHost: String
    private let expectedState: String
    private let fixedPort: UInt16?
    private let queue = DispatchQueue(label: "io.github.rollandxd.qingsongxiong.oauth-loopback")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var connections: [UUID: NWConnection] = [:]
    private var startWaiter: CheckedContinuation<UInt16, any Error>?
    private var callbackWaiter: CheckedContinuation<URL, any Error>?
    private var outcome: Result<URL, any Error>?
    private var timeout: Task<Void, Never>?

    init(path: String, host: String, state: String, fixedPort: UInt16?) {
        callbackPath = path
        callbackHost = host
        expectedState = state
        self.fixedPort = fixedPort
    }

    func start() async throws -> UInt16 {
        try Task.checkCancellation()
        guard listener == nil, outcome == nil else { throw UsageFailure.unavailable }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let requested = fixedPort.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requested)
        let candidate: NWListener
        do { candidate = try NWListener(using: parameters) } catch { throw UsageFailure.unavailable }
        listener = candidate
        candidate.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        candidate.stateUpdateHandler = { [weak self, weak candidate] state in
            switch state {
            case .ready:
                let port = candidate?.port?.rawValue ?? 0
                Task { await self?.didBind(port) }
            case .failed, .cancelled:
                Task { await self?.finish(.failure(UsageFailure.unavailable)) }
            default: break
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                candidate.start(queue: queue)
            }
        } onCancel: { Task { await self.cancel() } }
    }

    private func didBind(_ port: UInt16) {
        guard outcome == nil, let waiter = startWaiter else { return }
        guard port != 0 else { finish(.failure(UsageFailure.unavailable)); return }
        self.port = port
        startWaiter = nil
        waiter.resume(returning: port)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            await self?.finish(.failure(UsageFailure.authorizationTimedOut))
        }
    }

    public func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            if let outcome { return try outcome.get() }
            guard callbackWaiter == nil else { throw UsageFailure.unavailable }
            return try await withCheckedThrowingContinuation { callbackWaiter = $0 }
        } onCancel: { Task { await self.cancel() } }
    }

    public func cancel() { finish(.failure(CancellationError())); closeConnections() }
    func stop() { cancel() }

    private func finish(_ result: Result<URL, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        if let waiter = startWaiter {
            startWaiter = nil
            if case .failure(let error) = result { waiter.resume(throwing: error) }
            else { waiter.resume(throwing: UsageFailure.unavailable) }
        }
        if let waiter = callbackWaiter { callbackWaiter = nil; waiter.resume(with: result) }
        if case .failure = result { closeConnections() }
    }

    private func closeConnections() {
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard outcome == nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { await self?.consume(data, complete: complete || error != nil, connection: connection, id: id, buffer: buffer) }
        }
    }

    private func consume(_ data: Data?, complete: Bool, connection: NWConnection, id: UUID, buffer: Data) {
        guard outcome == nil, connections[id] != nil else { connection.cancel(); return }
        var received = buffer
        if let data { received.append(data) }
        guard received.count <= 16_384 else { respond(valid: false, connection: connection, id: id); return }
        if received.range(of: Data("\r\n\r\n".utf8)) == nil {
            if complete { connection.cancel(); connections[id] = nil }
            else { receive(connection, id: id, buffer: received) }
            return
        }
        guard let line = String(data: received, encoding: .utf8)?.components(separatedBy: "\r\n").first else {
            respond(valid: false, connection: connection, id: id); return
        }
        let fields = line.split(separator: " ")
        guard fields.count == 3, fields[0] == "GET", fields[1].hasPrefix("/"),
              let components = URLComponents(string: "http://\(callbackHost):\(port)" + String(fields[1])),
              components.path == callbackPath else { respond(valid: false, connection: connection, id: id); return }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }.compactMap(\.value)
        let codes = items.filter { $0.name == "code" }.compactMap(\.value)
        let errors = items.filter { $0.name == "error" }
        guard states == [expectedState], (codes.count == 1 && !codes[0].isEmpty) || errors.count == 1,
              let url = components.url else { respond(valid: false, connection: connection, id: id); return }
        respond(valid: true, connection: connection, id: id)
        finish(.success(url))
    }

    private func respond(valid: Bool, connection: NWConnection, id: UUID) {
        let message = valid ? "授权回调已收到，请返回轻松熊。" : "此请求无法用于完成授权。"
        let payload = Data(("<!doctype html><meta name=viewport content=width=device-width><p>" + message + "</p>").utf8)
        let status = valid ? "200 OK" : "400 Bad Request"
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { await self?.removeConnection(id) }
        })
    }

    private func removeConnection(_ id: UUID) { connections[id] = nil }
}
