import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SkipTVKit

func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
    }
    return try Data(contentsOf: url)
}

/// Transport returning canned responses by URL path; records requests.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        var status: Int
        var body: Data
    }

    private let lock = NSLock()
    private var stubs: [String: Stub] = [:]
    private var failing: Set<String> = []
    private(set) var requests: [URLRequest] = []

    func stub(_ path: String, status: Int = 200, body: Data) {
        lock.lock(); defer { lock.unlock() }
        stubs[path] = Stub(status: status, body: body)
    }

    func fail(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        failing.insert(path)
    }

    var recorded: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path
        let stub: Stub? = {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            if failing.contains(path) { return nil }
            return stubs[path] ?? Stub(status: 404, body: Data())
        }()
        guard let stub else { throw URLError(.cannotConnectToHost) }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (stub.body, response)
    }
}

extension URLRequest {
    func query(_ name: String) -> String? {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first { $0.name == name }?.value
    }
}

let testClient = PlexClientInfo(clientIdentifier: "test-client")
