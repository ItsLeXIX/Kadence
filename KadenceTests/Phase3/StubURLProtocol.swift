//
//  StubURLProtocol.swift
//  KadenceTests
//
//  The tests' HTTP stub (PHASE3-PLAN.md common rules: "HTTP goes through an
//  injected HTTPTransport: a URLProtocol stub in tests"). No request ever
//  leaves the process: `URLSessionTransport` is built with this protocol class
//  first in its configuration, and every request is answered here.
//
//  Swift Testing runs tests in parallel, so each test gets its own
//  `StubServer`, found through a session-level header the stub strips before
//  recording (`X-Kadence-Stub`).
//

import Foundation
import Synchronization
@testable import Kadence

/// What the stub does with one request.
nonisolated enum StubReply: Sendable {
    case response(HTTPResponseSpec)
    /// Fails before the request is "delivered": not recorded (the
    /// `certificate` and `offline` cases — nothing reached the server).
    case failBeforeSend(URLError.Code)
    /// Never answers: the transport's request timeout fires.
    case noAnswer
}

nonisolated struct HTTPResponseSpec: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body: Data = Data()
}

/// One request as the server saw it. `authorization` is the only place the
/// header's value exists (caldav-mocks.md §4 rule 3).
nonisolated struct StubRecord: Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data

    var host: String { url.host() ?? "" }
    var scheme: String { url.scheme ?? "" }
    var path: String { url.path(percentEncoded: true) }
    var authorization: String? { headers.first { $0.key.lowercased() == "authorization" }?.value }
    var hasAuthorization: Bool { authorization != nil }
    var depth: String? { headers.first { $0.key.lowercased() == "depth" }?.value }
    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

nonisolated final class StubServer: Sendable {
    private struct State {
        var records: [StubRecord] = []
        var inFlight = 0
        var maxInFlight = 0
    }
    private let state = Mutex(State())
    let token = UUID().uuidString
    let handler: @Sendable (StubRecord) -> StubReply

    init(_ handler: @escaping @Sendable (StubRecord) -> StubReply) {
        self.handler = handler
        StubRegistry.add(self)
    }

    deinit { StubRegistry.remove(token) }

    var records: [StubRecord] { state.withLock { $0.records } }
    /// caldav-mocks.md §4 rule 5: the stub never sees two requests in flight.
    var maxInFlight: Int { state.withLock { $0.maxInFlight } }

    /// A `URLSessionTransport` whose session can only reach this stub.
    func transport(timeout: TimeInterval = 30) -> URLSessionTransport {
        URLSessionTransport(requestTimeout: timeout, protocolClasses: [StubURLProtocol.self]) { configuration in
            var headers = configuration.httpAdditionalHeaders ?? [:]
            headers[StubURLProtocol.tokenHeader] = self.token
            configuration.httpAdditionalHeaders = headers
        }
    }

    fileprivate func begin(_ record: StubRecord) {
        state.withLock {
            $0.records.append(record)
            $0.inFlight += 1
            $0.maxInFlight = max($0.maxInFlight, $0.inFlight)
        }
    }

    fileprivate func end() { state.withLock { $0.inFlight -= 1 } }
}

nonisolated enum StubRegistry {
    private static let servers = Mutex<[String: WeakServer]>([:])
    private struct WeakServer: @unchecked Sendable { weak var server: StubServer? }

    static func add(_ server: StubServer) { servers.withLock { $0[server.token] = WeakServer(server: server) } }
    static func remove(_ token: String) { _ = servers.withLock { $0.removeValue(forKey: token) } }
    static func server(_ token: String?) -> StubServer? {
        guard let token else { return nil }
        return servers.withLock { $0[token]?.server }
    }
}

/// Swift note: `URLProtocol` is Foundation's plug-in point for URL loading —
/// the session asks each registered class `canInit`, then calls
/// `startLoading`, and the class answers through `client`.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let tokenHeader = "X-Kadence-Stub"
    private let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader)
        guard let server = StubRegistry.server(token), let url = request.url else {
            // No server: never touch the network — fail as offline.
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: Self.tokenHeader)
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let record = StubRecord(method: request.httpMethod ?? "GET", url: url, headers: headers, body: body)
        let reply = server.handler(record)
        if case .failBeforeSend(let code) = reply {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        server.begin(record)
        switch reply {
        case .response(let spec):
            let response = HTTPURLResponse(url: url, statusCode: spec.status, httpVersion: "HTTP/1.1",
                                           headerFields: spec.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: spec.body)
            client?.urlProtocolDidFinishLoading(self)
            server.end()
        case .noAnswer:
            // Held until the session's timeout cancels us (`stopLoading`).
            lock.withLock { pendingServer = server }
        case .failBeforeSend:
            break
        }
    }

    private var pendingServer: StubServer?

    override func stopLoading() {
        lock.withLock {
            pendingServer?.end()
            pendingServer = nil
        }
    }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
