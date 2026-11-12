import Foundation

/// One request the crawl or an engine makes.
public struct FetchRequest: Sendable {
    public var url: URL
    public var method: String = "GET"
    public var body: Data?
    public var headers: [String: String] = [:]
    public var timeout: TimeInterval = 10
    public var maxBytes: Int = 2 << 20

    public init(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], timeout: TimeInterval = 10,
                maxBytes: Int = 2 << 20) {
        self.url = url; self.method = method; self.body = body; self.headers = headers; self.timeout = timeout; self.maxBytes = maxBytes
    }
}

/// What came back: where the request ended, its status, its type and as much of its body as the cap allows.
public struct Fetched: Sendable {
    public var url: URL
    public var status: Int
    public var mimeType: String?
    public var encoding: String?
    public var data: Data
    /// The body was longer than the cap and was cut there.
    public var truncated: Bool

    public init(url: URL, status: Int, mimeType: String?, encoding: String? = nil, data: Data, truncated: Bool = false) {
        self.url = url; self.status = status; self.mimeType = mimeType; self.encoding = encoding; self.data = data; self.truncated = truncated
    }

    /// The body as text, by the encoding the response named, else UTF-8, else Latin-1.
    public var text: String {
        if let name = encoding {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId,
               let decoded = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return decoded
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

public enum FetchError: Error, Equatable, CustomStringConvertible {
    case refused(String)
    case unreachable(String)
    case timedOut
    case unrecorded(String)

    public var description: String {
        switch self {
        case .refused(let why): return why
        case .unreachable(let why): return "unreachable: \(why)"
        case .timedOut: return "timed out"
        case .unrecorded: return "not recorded"
        }
    }

    /// The network failed, not the page: nothing answered, or nothing in time.
    public var isNetwork: Bool {
        switch self {
        case .unreachable, .timedOut: return true
        case .refused, .unrecorded: return false
        }
    }
}

/// How the run reaches the web: live, or from recorded answers in tests.
public protocol Fetching: Sendable {
    func fetch(_ request: FetchRequest) async throws -> Fetched
    /// Whether a host's addresses are checked before it is read: the live web's are; a recording has none.
    var resolvesHosts: Bool { get }
}

extension Fetching {
    public var resolvesHosts: Bool { true }
}

/// What the agent says it is, to every site it reads.
public enum WebIdentity {
    public static let userAgent = "WebAgent/1 (+https://github.com/rao-craft/WebAgent)"
    public static let robotsName = "webagent"
}

/// The live web, isolated: a session of its own per call that keeps no cookie, cache, credential or URL, offers no
/// login, follows at most five redirects, each to a public host, and stops reading a body at its cap.
public final class IsolatedFetcher: Fetching, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": WebIdentity.userAgent,
            "Accept-Language": "en-US,en;q=0.8",
        ]
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    public func fetch(_ request: FetchRequest) async throws -> Fetched {
        guard HostGuard.check(request.url) == .allowed else { throw FetchError.refused("not a public web address") }
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        if urlRequest.value(forHTTPHeaderField: "Accept") == nil {
            urlRequest.setValue("text/html,application/xhtml+xml,application/pdf,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        }
        let guardian = RedirectGuard()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: urlRequest, delegate: guardian)
        } catch let error as URLError where error.code == .timedOut {
            throw FetchError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            if let refused = guardian.refusal { throw FetchError.refused(refused) }
            throw CancellationError()
        } catch {
            if let refused = guardian.refusal { throw FetchError.refused(refused) }
            throw FetchError.unreachable((error as? URLError)?.localizedDescription ?? "\(error)")
        }
        // A redirect refused ends the task on the redirect's own response: it is the refusal, not the page.
        if let refused = guardian.refusal { throw FetchError.refused(refused) }
        var data = Data()
        let expected = response.expectedContentLength
        if expected > 0 { data.reserveCapacity(min(Int(expected), request.maxBytes)) }
        var truncated = false
        do {
            for try await byte in bytes {
                if data.count >= request.maxBytes { truncated = true; break }
                data.append(byte)
            }
        } catch let error as URLError where error.code == .timedOut {
            if data.isEmpty { throw FetchError.timedOut }
            truncated = true
        }
        let http = response as? HTTPURLResponse
        return Fetched(url: response.url ?? request.url, status: http?.statusCode ?? 200, mimeType: response.mimeType,
                       encoding: response.textEncodingName, data: data, truncated: truncated)
    }
}

/// Each redirect checked as the first request was, five at most; no credential is ever offered.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirects = 0
    private var refused: String?

    var refusal: String? { lock.withLock { refused } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        let count = lock.withLock { redirects += 1; return redirects }
        guard count <= 5 else { lock.withLock { refused = "more than five redirects" }; return nil }
        guard let url = request.url else { return nil }
        if case .refused(let why) = await HostGuard.checkResolving(url) {
            lock.withLock { refused = "redirected to \(why)" }
            return nil
        }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // A server's certificate is checked as the system checks it; a login is never answered.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { return (.performDefaultHandling, nil) }
        return (.cancelAuthenticationChallenge, nil)
    }
}
