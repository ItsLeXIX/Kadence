//
//  HTTPTransport.swift
//  Kadence
//
//  PHASE3-PLAN.md task 5 — the only way Kadence speaks HTTP. components.md
//  §21.4 (ephemeral session, no cache, no credential storage, no redirects
//  followed), interactions.md §13.1 (the account on the wire).
//
//  Every request goes through an injected `HTTPTransport`: `URLSessionTransport`
//  in the app, a `URLProtocol` stub in tests, `MockCalDAVTransport` in review
//  mode. Nothing here logs a header or a body.
//

import Foundation
import CryptoKit

// MARK: - Values

nonisolated struct HTTPRequest: Sendable, Equatable {
    var method: String
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?

    /// The value of a header, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

nonisolated struct HTTPResponse: Sendable, Equatable {
    var status: Int
    /// Header names lower-cased.
    var headers: [String: String] = [:]
    var body: Data = Data()
    var url: URL

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// How a request failed below HTTP. No case carries a URL, header or body.
nonisolated enum TransportError: Error, Equatable, Sendable {
    /// `URLError.notConnectedToInternet` — a state, not an error (§13.3).
    case offline
    case timeout
    /// DNS, refused, lost.
    case unreachable
    /// TLS: nothing was sent (§13.1).
    case certificate
    /// A response over `URLSessionTransport.maxResponseBytes` (§20.8.2).
    case tooLarge
    case cancelled

    static func from(_ error: URLError) -> TransportError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: .offline
        case .timedOut: .timeout
        case .cancelled: .cancelled
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired,
             .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection: .certificate
        default: .unreachable
        }
    }
}

nonisolated protocol HTTPTransport: Sendable {
    /// Sends one request and returns the response as it came — a `3xx`
    /// included: a transport never follows a redirect (§21.4).
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse
}

// MARK: - The credential and the challenge (interactions.md §13.1)

/// Answers a host's `401` with the password, for that host, port and `https`
/// only. Armed per connect or per sync, never stored.
///
/// Kadence builds the `Authorization` header itself instead of handing a
/// `URLCredential` to Foundation (DEVIATIONS B40): the same code then runs
/// against the real server and against the tests' `URLProtocol` stub, and no
/// Foundation credential store is involved at all.
nonisolated struct ChallengeResponder: Sendable {
    var host: String
    var port: Int
    var username: String
    var password: Password

    init(host: String, port: Int = 443, username: String, password: Password) {
        self.host = host.lowercased(); self.port = port; self.username = username; self.password = password
    }

    /// Whether `url` is this credential's protection space: same host, same
    /// port, and `https`. Everything else is declined.
    func covers(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let h = url.host()?.lowercased(), h == host else { return false }
        return (url.port ?? 443) == port
    }

    /// The `Authorization` value for a `WWW-Authenticate` challenge from
    /// `url`, or nil when the challenge is declined (another host, `http:`,
    /// an unknown scheme).
    func authorization(for request: HTTPRequest, challenge: String?) -> String? {
        guard covers(request.url) else { return nil }
        let scheme = challenge?.split(separator: " ", maxSplits: 1).first.map { $0.lowercased() } ?? "basic"
        switch scheme {
        case "basic":
            return password.withPlaintext { "Basic " + Data("\(username):\($0)".utf8).base64EncodedString() }
        case "digest":
            return digest(request: request, challenge: challenge ?? "")
        default:
            return nil
        }
    }

    /// The header for a request in a sync whose host has already challenged:
    /// the same protection space, so the same answer (§13.1).
    func authorizationAfterChallenge(for request: HTTPRequest, scheme: String?) -> String? {
        guard covers(request.url) else { return nil }
        return authorization(for: request, challenge: scheme)
    }

    /// RFC 7616 Digest (MD5, `qop=auth` when offered). Swift note:
    /// `Insecure.MD5` is CryptoKit's name for a hash kept for protocols, not
    /// for new security — which is exactly this use.
    private func digest(request: HTTPRequest, challenge: String) -> String? {
        let params = Self.parameters(challenge)
        guard let realm = params["realm"], let nonce = params["nonce"] else { return nil }
        if let algorithm = params["algorithm"], algorithm.uppercased() != "MD5" { return nil }
        func md5(_ s: String) -> String { Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        var path = request.url.path(percentEncoded: true)
        if path.isEmpty { path = "/" }
        if let q = request.url.query(percentEncoded: true) { path += "?" + q }
        let ha1 = password.withPlaintext { md5("\(username):\(realm):\($0)") }
        let ha2 = md5("\(request.method):\(path)")
        let qops = params["qop"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        var header = "Digest username=\"\(username)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(path)\""
        if qops.contains("auth") {
            let cnonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            let nc = "00000001"
            header += ", qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(md5("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)"))\""
        } else {
            header += ", response=\"\(md5("\(ha1):\(nonce):\(ha2)"))\""
        }
        if let opaque = params["opaque"] { header += ", opaque=\"\(opaque)\"" }
        return header + ", algorithm=MD5"
    }

    static func parameters(_ challenge: String) -> [String: String] {
        var out: [String: String] = [:]
        let body = challenge.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        var key = "", value = "", inKey = true, inQuotes = false
        func flush() {
            let k = key.trimmingCharacters(in: .whitespaces).lowercased()
            if !k.isEmpty { out[k] = value.trimmingCharacters(in: .whitespaces) }
            key = ""; value = ""; inKey = true
        }
        for c in body {
            if inKey { if c == "=" { inKey = false } else if c != "," { key.append(c) }; continue }
            if c == "\"" { inQuotes.toggle(); continue }
            if c == "," && !inQuotes { flush(); continue }
            value.append(c)
        }
        flush()
        return out
    }
}

// MARK: - URLSession

/// The app's transport. One instance = one ephemeral session = one connect or
/// one sync (§21.4: "a fresh session per connect and per sync").
nonisolated final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    /// §20.8.2: one response over 20 MB is not read.
    static let maxResponseBytes = 20 * 1_048_576

    /// Swift note: `@unchecked Sendable` — `URLSession` is thread-safe but not
    /// marked `Sendable`; `session` is set once in `init` and never again.
    /// (`!` is the implicitly unwrapped optional: it has to be assigned after
    /// `super.init()`, because the session's delegate is `self`.)
    private(set) var session: URLSession!
    let requestTimeout: TimeInterval

    /// `protocolClasses` and `configure` let tests insert their `URLProtocol`
    /// stub into this exact configuration; the app passes neither.
    /// `cookies: false` is the feed's configuration (components.md §33.4
    /// obligation 3): no cookie storage at all, none sent, none accepted.
    init(requestTimeout: TimeInterval = 30, cookies: Bool = true, protocolClasses: [AnyClass]? = nil,
         configure: ((URLSessionConfiguration) -> Void)? = nil) {
        self.requestTimeout = requestTimeout
        super.init()
        let configuration = Self.configuration(requestTimeout: requestTimeout, cookies: cookies)
        if let protocolClasses { configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? []) }
        configure?(configuration)
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// §21.4: ephemeral, no URL cache, no credential storage; cookies live in
    /// this session's memory only.
    static func configuration(requestTimeout: TimeInterval, cookies: Bool = true) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = requestTimeout
        if cookies {
            c.httpShouldSetCookies = true
            c.httpCookieAcceptPolicy = .always
        } else {
            // §33.4 obligation 3: no HTTP state of any kind for a feed.
            c.httpCookieStorage = nil
            c.httpShouldSetCookies = false
            c.httpCookieAcceptPolicy = .never
        }
        return c
    }

    /// Ends the session (a session holds its delegate strongly, so every
    /// connect and sync calls this when it is done).
    func invalidate() { session.invalidateAndCancel() }

    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData,
                                    timeoutInterval: requestTimeout)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw TransportError.unreachable }
            guard data.count <= Self.maxResponseBytes else { throw TransportError.tooLarge }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String { headers[k.lowercased()] = "\(value)" }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data, url: http.url ?? request.url)
        } catch let error as TransportError {
            throw error
        } catch let error as URLError {
            throw TransportError.from(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unreachable
        }
    }

    // MARK: URLSessionTaskDelegate

    /// Never follow: hand the `3xx` back to the client, which decides
    /// (interactions.md §13.1).
    ///
    /// (The completion-handler form, not the `async` one: Swift 6.4's
    /// compiler crashes emitting the Objective-C thunk for the latter.)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Foundation never answers a password challenge by itself: the 401 comes
    /// back to the client, whose `ChallengeResponder` decides. Server trust
    /// takes the system's default evaluation, so an untrusted certificate
    /// fails the task before any request line is written.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust: completionHandler(.performDefaultHandling, nil)
        default: completionHandler(.rejectProtectionSpace, nil)
        }
    }
}
