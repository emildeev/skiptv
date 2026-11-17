import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction so that API clients can be tested with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum HTTPError: Error, Equatable, Sendable {
    case notHTTP
    case status(Int)
    case invalidURL(String)
}

/// `URLSession`-backed transport. Uses the callback API so it also works on Linux.
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: HTTPError.notHTTP)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}

extension HTTPTransport {
    /// Sends the request and fails on non-2xx status codes.
    func sendChecked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError.status(response.statusCode)
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let data = try await sendChecked(request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension URL {
    /// Appends a path that may already contain a query string (Plex keys like `/library/x?y=1`).
    func appendingPlexPath(_ path: String, query: [URLQueryItem] = []) -> URL? {
        var base = absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let joined = path.hasPrefix("/") ? base + path : base + "/" + path
        guard var components = URLComponents(string: joined) else { return nil }
        if !query.isEmpty {
            let encoded = query.map { item in
                URLQueryItem(name: item.name.strictQueryEncoded, value: item.value?.strictQueryEncoded)
            }
            components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? []) + encoded
        }
        return components.url
    }
}

extension String {
    /// Percent-encodes everything except RFC 3986 unreserved characters,
    /// so nested URLs (`url=/a?b=1&c=2`) survive as a single query value.
    var strictQueryEncoded: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
