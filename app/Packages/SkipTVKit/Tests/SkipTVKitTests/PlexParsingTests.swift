import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SkipTVKit

final class PlexParsingTests: XCTestCase {
    func testSections() throws {
        let response = try JSONDecoder().decode(PlexResponse<DirectoryContainer>.self, from: fixture("sections"))
        let sections = response.mediaContainer.directories
        XCTAssertEqual(sections.map(\.title), ["Фильмы", "Сериалы", "Музыка"])
        XCTAssertEqual(sections.map(\.kind), [.movie, .show, .artist])
    }

    func testEpisodeWithMedia() throws {
        let response = try JSONDecoder().decode(PlexResponse<MetadataContainer>.self, from: fixture("episode"))
        let item = try XCTUnwrap(response.mediaContainer.metadata.first)
        XCTAssertEqual(item.ratingKey, "12345")
        XCTAssertEqual(item.type, .episode)
        XCTAssertEqual(item.index, 3)
        XCTAssertEqual(item.parentIndex, 2)
        XCTAssertEqual(item.viewCount, 1, "string number must be accepted")
        XCTAssertEqual(item.episodeLabel, "S2 · E3")
        XCTAssertEqual(item.displayTitle, "Тестовый сериал")
        XCTAssertEqual(item.displaySubtitle, "S2 · E3 — Пилот")
        XCTAssertEqual(item.showRatingKey, "12200")
        XCTAssertEqual(item.posterPath, "/library/metadata/12200/thumb/1700000000")
        XCTAssertEqual(item.landscapePath, "/library/metadata/12345/thumb/1700000000")
        XCTAssertEqual(try XCTUnwrap(item.progress), 615.0 / 2990.0, accuracy: 0.0001)
        XCTAssertFalse(item.isWatched)

        let part = try XCTUnwrap(item.primaryPart)
        XCTAssertEqual(part.key, "/library/parts/777/1690000000/file.mkv")
        XCTAssertEqual(part.size, 25_123_456_789)
        XCTAssertEqual(part.streams.count, 5)
        XCTAssertEqual(part.streams.filter { $0.kind == .audio }.map(\.languageCode), ["eng", "rus"])
        XCTAssertEqual(part.streams.last?.key, "/library/streams/5")
        XCTAssertEqual(item.media.first?.videoCodec, "hevc")
        XCTAssertEqual(item.media.first?.dynamicRangeBadge, "DOLBY VISION")
    }

    func testSeasonsWatchedCounts() throws {
        let seasons = try JSONDecoder().decode(PlexResponse<MetadataContainer>.self, from: fixture("seasons")).mediaContainer.metadata
        XCTAssertEqual(seasons.map(\.type), [.season, .season])
        XCTAssertTrue(seasons[0].isWatched)
        XCTAssertFalse(seasons[1].isWatched)
        XCTAssertEqual(seasons[1].unwatchedLeafCount, 5)
    }

    func testEmptyContainer() throws {
        let data = Data(#"{"MediaContainer":{"size":0}}"#.utf8)
        let response = try JSONDecoder().decode(PlexResponse<MetadataContainer>.self, from: data)
        XCTAssertEqual(response.mediaContainer.metadata, [])
    }

    func testWatchedMovie() throws {
        let data = Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":5,"type":"movie","title":"M","viewCount":2}]}}"#.utf8)
        let item = try XCTUnwrap(JSONDecoder().decode(PlexResponse<MetadataContainer>.self, from: data).mediaContainer.metadata.first)
        XCTAssertEqual(item.ratingKey, "5", "numeric ratingKey is accepted")
        XCTAssertTrue(item.isWatched)
        XCTAssertNil(item.progress)
    }
}

final class PlexAccountTests: XCTestCase {
    func testServersFromResources() async throws {
        let transport = MockTransport()
        transport.stub("/api/v2/resources", body: try fixture("resources"))
        let api = PlexAccountAPI(client: testClient, transport: transport)

        let servers = try await api.servers(token: "user-token")
        XCTAssertEqual(servers.count, 1, "players are not servers")
        let server = try XCTUnwrap(servers.first)
        XCTAssertEqual(server.name, "Home")
        XCTAssertEqual(server.accessToken, "server-token")

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Token"), "user-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "test-client")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.query("includeHttps"), "1")
    }

    func testCandidateURLOrder() throws {
        let server = try XCTUnwrap(JSONDecoder().decode([PlexResource].self, from: fixture("resources")).first)
        let plexServer = PlexServer(name: server.name, clientIdentifier: server.clientIdentifier, accessToken: "t", connections: server.connections ?? [])
        XCTAssertEqual(plexServer.candidateURLs.map(\.absoluteString), [
            "https://192-168-0-10.abc.plex.direct:32400",
            "http://192.168.0.10:32400",
            "https://203-0-113-10.abc.plex.direct:32400",
            "https://plex.emill.keenetic.pro",
            "https://198-51-100-1.abc.plex.direct:8443",
        ])
    }

    func testPinFlow() async throws {
        let transport = MockTransport()
        transport.stub("/api/v2/pins", status: 201, body: Data(#"{"id":42,"code":"AB12","authToken":null,"expiresIn":900}"#.utf8))
        transport.stub("/api/v2/pins/42", body: Data(#"{"id":42,"code":"AB12","authToken":"secret"}"#.utf8))
        let api = PlexAccountAPI(client: testClient, transport: transport)

        let pin = try await api.createPin()
        XCTAssertEqual(pin, PlexPin(id: 42, code: "AB12", authToken: nil, expiresIn: 900))
        XCTAssertEqual(transport.recorded.first?.httpMethod, "POST")
        XCTAssertEqual(transport.recorded.first?.query("strong"), "false")
        XCTAssertEqual(transport.recorded.first?.value(forHTTPHeaderField: "X-Plex-Product"), "SkipTV")

        let checked = try await api.checkPin(id: 42)
        XCTAssertEqual(checked.authToken, "secret")
    }
}

final class PlexServerAPITests: XCTestCase {
    let base = URL(string: "http://server.test:32400")!

    func testFirstReachablePrefersOrder() async {
        let transport = MockTransport()
        transport.fail("/identity")
        let local = URL(string: "http://local.test:32400")!
        let remote = URL(string: "https://remote.test")!
        // Both fail → nil.
        let none = await PlexServerAPI.firstReachable([local, remote], token: "t", client: testClient, transport: transport)
        XCTAssertNil(none)

        let ok = HostTransport(reachable: ["remote.test", "local.test"])
        let both = await PlexServerAPI.firstReachable([local, remote], token: "t", client: testClient, transport: ok)
        XCTAssertEqual(both, local)

        let onlyRemote = HostTransport(reachable: ["remote.test"])
        let chosen = await PlexServerAPI.firstReachable([local, remote], token: "t", client: testClient, transport: onlyRemote)
        XCTAssertEqual(chosen, remote)
    }

    func testTimelineAndScrobble() async throws {
        let transport = MockTransport()
        transport.stub("/:/timeline", body: Data())
        transport.stub("/:/scrobble", body: Data())
        let api = PlexServerAPI(baseURL: base, token: "tok", client: testClient, transport: transport)
        let item = PlexItem(ratingKey: "12345", type: .episode, title: "x")

        try await api.reportTimeline(item: item, state: .paused, position: 61.7, duration: 2990)
        let timeline = try XCTUnwrap(transport.recorded.last)
        XCTAssertEqual(timeline.query("ratingKey"), "12345")
        XCTAssertEqual(timeline.query("key"), "/library/metadata/12345")
        XCTAssertEqual(timeline.query("state"), "paused")
        XCTAssertEqual(timeline.query("time"), "61700")
        XCTAssertEqual(timeline.query("duration"), "2990000")
        XCTAssertEqual(timeline.value(forHTTPHeaderField: "X-Plex-Token"), "tok")
        XCTAssertEqual(timeline.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "test-client")

        try await api.markWatched(ratingKey: "12345")
        let scrobble = try XCTUnwrap(transport.recorded.last)
        XCTAssertEqual(scrobble.url?.path, "/:/scrobble")
        XCTAssertEqual(scrobble.query("key"), "12345")
        XCTAssertEqual(scrobble.query("identifier"), "com.plexapp.plugins.library")
    }

    func testURLs() throws {
        let api = PlexServerAPI(baseURL: URL(string: "https://plex.example/")!, token: "tok", client: testClient)
        let part = PlexPart(id: "1", key: "/library/parts/777/1690000000/file.mkv")
        XCTAssertEqual(api.directPlayURL(part)?.absoluteString,
                       "https://plex.example/library/parts/777/1690000000/file.mkv?X-Plex-Token=tok")

        let image = try XCTUnwrap(api.imageURL("/library/metadata/1/thumb/2?a=1&b=2", width: 300, height: 450))
        let items = try XCTUnwrap(URLComponents(url: image, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(image.path, "/photo/:/transcode")
        XCTAssertEqual(items.first { $0.name == "url" }?.value, "/library/metadata/1/thumb/2?a=1&b=2")
        XCTAssertEqual(items.first { $0.name == "width" }?.value, "300")
        XCTAssertNil(api.imageURL(nil, width: 1, height: 1))
    }

    func testItemsQuery() async throws {
        let transport = MockTransport()
        transport.stub("/library/sections/2/all", body: try fixture("seasons"))
        let api = PlexServerAPI(baseURL: base, token: "tok", client: testClient, transport: transport)
        _ = try await api.items(section: PlexLibrarySection(key: "2", title: "Сериалы", type: "show"))
        XCTAssertEqual(transport.recorded.last?.query("type"), "2")
        XCTAssertEqual(transport.recorded.last?.query("sort"), "titleSort")
    }

    func testServerErrorThrows() async {
        let transport = MockTransport()
        transport.stub("/library/onDeck", status: 401, body: Data())
        let api = PlexServerAPI(baseURL: base, token: "tok", client: testClient, transport: transport)
        do {
            _ = try await api.onDeck()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? HTTPError, .status(401))
        }
    }
}

/// Answers 200 only for the given hosts.
struct HostTransport: HTTPTransport {
    var reachable: Set<String>

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        guard let host = url.host, reachable.contains(host) else { throw URLError(.timedOut) }
        return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
