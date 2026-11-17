import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PlaybackState: String, Sendable {
    case playing, paused, stopped, buffering
}

/// Plex Media Server API bound to one reachable base URL.
public struct PlexServerAPI: Sendable {
    public let baseURL: URL
    public let token: String
    public let client: PlexClientInfo
    public let transport: HTTPTransport

    public init(baseURL: URL, token: String, client: PlexClientInfo, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
        self.transport = transport
    }

    // MARK: Connection

    /// Probes candidate URLs in parallel and returns the most preferred reachable one.
    public static func firstReachable(
        _ candidates: [URL],
        token: String,
        client: PlexClientInfo,
        transport: HTTPTransport = URLSessionTransport(),
        timeout: TimeInterval = 4
    ) async -> URL? {
        let results = await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, url) in candidates.enumerated() {
                group.addTask {
                    guard let probe = url.appendingPlexPath("/identity") else { return (i, false) }
                    let request = client.request(probe, token: token, timeout: timeout)
                    do {
                        let (_, response) = try await transport.send(request)
                        return (i, (200..<300).contains(response.statusCode))
                    } catch {
                        return (i, false)
                    }
                }
            }
            var ok: [Int: Bool] = [:]
            for await (i, reachable) in group { ok[i] = reachable }
            return ok
        }
        return candidates.indices.first { results[$0] == true }.map { candidates[$0] }
    }

    // MARK: Requests

    func url(_ path: String, _ query: [String: String] = [:]) throws -> URL {
        let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = baseURL.appendingPlexPath(path, query: items) else {
            throw HTTPError.invalidURL(path)
        }
        return url
    }

    func metadata(_ path: String, _ query: [String: String] = [:]) async throws -> [PlexItem] {
        let request = client.request(try url(path, query), token: token)
        return try await transport.decode(PlexResponse<MetadataContainer>.self, from: request).mediaContainer.metadata
    }

    public func sections() async throws -> [PlexLibrarySection] {
        let request = client.request(try url("/library/sections"), token: token)
        return try await transport.decode(PlexResponse<DirectoryContainer>.self, from: request).mediaContainer.directories
    }

    /// All movies or shows of a library section, sorted by title.
    public func items(section: PlexLibrarySection) async throws -> [PlexItem] {
        var query = ["sort": "titleSort"]
        switch section.kind {
        case .movie: query["type"] = "1"
        case .show: query["type"] = "2"
        default: break
        }
        return try await metadata("/library/sections/\(section.key)/all", query)
    }

    /// "Continue watching": in-progress items and next episodes.
    public func onDeck() async throws -> [PlexItem] {
        try await metadata("/library/onDeck")
    }

    public func recentlyAdded(section: PlexLibrarySection, limit: Int = 30) async throws -> [PlexItem] {
        try await metadata("/library/sections/\(section.key)/recentlyAdded", [
            "X-Plex-Container-Start": "0",
            "X-Plex-Container-Size": String(limit),
        ])
    }

    /// Full item with media parts and streams.
    public func item(ratingKey: String) async throws -> PlexItem? {
        try await metadata("/library/metadata/\(ratingKey)").first
    }

    /// Seasons of a show or episodes of a season.
    public func children(ratingKey: String) async throws -> [PlexItem] {
        try await metadata("/library/metadata/\(ratingKey)/children")
    }

    /// All episodes of a show in order.
    public func allEpisodes(showRatingKey: String) async throws -> [PlexItem] {
        try await metadata("/library/metadata/\(showRatingKey)/allLeaves")
    }

    // MARK: Watch state

    /// Reports playback progress so other Plex clients see "continue watching".
    public func reportTimeline(item: PlexItem, state: PlaybackState, position: TimeInterval, duration: TimeInterval?) async throws {
        var query = [
            "ratingKey": item.ratingKey,
            "key": item.key,
            "state": state.rawValue,
            "time": String(Int(position * 1000)),
            "hasMDE": "1",
        ]
        if let duration, duration > 0 {
            query["duration"] = String(Int(duration * 1000))
        }
        _ = try await transport.sendChecked(client.request(try url("/:/timeline", query), token: token))
    }

    public func markWatched(ratingKey: String) async throws {
        _ = try await transport.sendChecked(client.request(try url("/:/scrobble", [
            "identifier": "com.plexapp.plugins.library",
            "key": ratingKey,
        ]), token: token))
    }

    public func markUnwatched(ratingKey: String) async throws {
        _ = try await transport.sendChecked(client.request(try url("/:/unscrobble", [
            "identifier": "com.plexapp.plugins.library",
            "key": ratingKey,
        ]), token: token))
    }

    // MARK: URLs

    /// Resized image through the server's photo transcoder.
    public func imageURL(_ path: String?, width: Int, height: Int) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        return baseURL.appendingPlexPath("/photo/:/transcode", query: [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ])
    }

    /// Original file for direct play (no transcoding).
    public func directPlayURL(_ part: PlexPart) -> URL? {
        baseURL.appendingPlexPath(part.key, query: [URLQueryItem(name: "X-Plex-Token", value: token)])
    }
}
