import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PIN created on plex.tv; the user enters `code` at plex.tv/link.
public struct PlexPin: Decodable, Equatable, Sendable {
    public var id: Int
    public var code: String
    public var authToken: String?
    public var expiresIn: Int?

    public init(id: Int, code: String, authToken: String? = nil, expiresIn: Int? = nil) {
        self.id = id
        self.code = code
        self.authToken = authToken
        self.expiresIn = expiresIn
    }
}

public struct PlexConnection: Codable, Hashable, Sendable {
    public var uri: String
    public var local: Bool
    public var relay: Bool
    public var address: String?
    public var port: Int?
    public var `protocol`: String?

    public init(uri: String, local: Bool, relay: Bool = false, address: String? = nil, port: Int? = nil, protocol: String? = nil) {
        self.uri = uri
        self.local = local
        self.relay = relay
        self.address = address
        self.port = port
        self.protocol = `protocol`
    }

    enum CodingKeys: String, CodingKey {
        case uri, local, relay, address, port, `protocol`
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(String.self, forKey: .uri)
        local = (try? c.decodeIfPresent(Bool.self, forKey: .local)) ?? false
        relay = (try? c.decodeIfPresent(Bool.self, forKey: .relay)) ?? false
        address = c.lossyString(.address)
        port = c.lossyInt(.port)
        self.protocol = c.lossyString(.protocol)
    }
}

/// A Plex Media Server the account has access to.
public struct PlexServer: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var clientIdentifier: String
    public var accessToken: String
    public var owned: Bool
    public var connections: [PlexConnection]

    public var id: String { clientIdentifier }

    public init(name: String, clientIdentifier: String, accessToken: String, owned: Bool = true, connections: [PlexConnection]) {
        self.name = name
        self.clientIdentifier = clientIdentifier
        self.accessToken = accessToken
        self.owned = owned
        self.connections = connections
    }

    /// Candidate base URLs in order of preference: local, remote, relay.
    /// For local connections a plain `http://address:port` is added after the
    /// `plex.direct` one, because routers often block DNS rebinding of plex.direct.
    public var candidateURLs: [URL] {
        func rank(_ c: PlexConnection) -> Int {
            if c.relay { return 2 }
            return c.local ? 0 : 1
        }
        var result: [String] = []
        let sorted = connections.enumerated().sorted { lhs, rhs in
            let l = rank(lhs.element), r = rank(rhs.element)
            return l != r ? l < r : lhs.offset < rhs.offset
        }
        for (_, connection) in sorted {
            result.append(connection.uri)
            if connection.local, !connection.relay, let address = connection.address, !address.contains(":") {
                result.append("http://\(address):\(connection.port ?? 32400)")
            }
        }
        var seen = Set<String>()
        return result
            .filter { seen.insert($0).inserted }
            .compactMap(URL.init(string:))
    }
}

/// Raw `api/v2/resources` entry.
struct PlexResource: Decodable {
    var name: String
    var clientIdentifier: String
    var provides: String?
    var accessToken: String?
    var owned: Bool?
    var connections: [PlexConnection]?
}

/// plex.tv account API: PIN login and server discovery.
public struct PlexAccountAPI: Sendable {
    public static let defaultBase = URL(string: "https://plex.tv")!

    public let client: PlexClientInfo
    public let transport: HTTPTransport
    public let base: URL

    public init(client: PlexClientInfo, transport: HTTPTransport = URLSessionTransport(), base: URL = PlexAccountAPI.defaultBase) {
        self.client = client
        self.transport = transport
        self.base = base
    }

    public static let linkURL = "plex.tv/link"

    /// Creates a short (4 character) PIN for plex.tv/link.
    public func createPin() async throws -> PlexPin {
        guard let url = base.appendingPlexPath("/api/v2/pins", query: [URLQueryItem(name: "strong", value: "false")]) else {
            throw HTTPError.invalidURL("pins")
        }
        return try await transport.decode(PlexPin.self, from: client.request(url, method: "POST"))
    }

    /// Returns the PIN; `authToken` is set once the user has linked the code.
    public func checkPin(id: Int) async throws -> PlexPin {
        guard let url = base.appendingPlexPath("/api/v2/pins/\(id)") else {
            throw HTTPError.invalidURL("pin")
        }
        return try await transport.decode(PlexPin.self, from: client.request(url))
    }

    /// Media servers available to the account.
    public func servers(token: String) async throws -> [PlexServer] {
        guard let url = base.appendingPlexPath("/api/v2/resources", query: [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]) else {
            throw HTTPError.invalidURL("resources")
        }
        let resources = try await transport.decode([PlexResource].self, from: client.request(url, token: token))
        return resources
            .filter { ($0.provides ?? "").split(separator: ",").contains("server") }
            .map {
                PlexServer(
                    name: $0.name,
                    clientIdentifier: $0.clientIdentifier,
                    accessToken: $0.accessToken ?? token,
                    owned: $0.owned ?? false,
                    connections: $0.connections ?? []
                )
            }
    }
}
