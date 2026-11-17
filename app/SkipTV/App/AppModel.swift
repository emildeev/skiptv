import Foundation
import Observation
import SkipTVKit
import UIKit

/// What to play and from where; presented full screen.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    var item: PlexItem
    /// Seconds; nil starts from the beginning.
    var startAt: Double?
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case login
        case choosingServer([PlexServer])
        case connecting(String)
        case failed(String)
        case ready
    }

    var phase: Phase = .starting
    let settings = AppSettings()
    let clientInfo: PlexClientInfo

    private(set) var userToken: String?
    private(set) var server: PlexServer?
    private(set) var api: PlexServerAPI?
    private(set) var sections: [PlexLibrarySection] = []

    /// Currently presented player.
    var playback: PlaybackRequest?
    /// Item waiting for the "Resume / From the beginning" choice.
    var resumeCandidate: PlexItem?
    /// Bumped after playback so screens reload watch state.
    private(set) var refreshID = 0

    init() {
        let identifier: String
        if let stored = Keychain.string(StorageKey.clientIdentifier) {
            identifier = stored
        } else {
            identifier = UUID().uuidString
            Keychain.setString(identifier, for: StorageKey.clientIdentifier)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        clientInfo = PlexClientInfo(
            clientIdentifier: identifier,
            version: version,
            platformVersion: UIDevice.current.systemVersion,
            deviceName: UIDevice.current.name
        )
    }

    var account: PlexAccountAPI { PlexAccountAPI(client: clientInfo) }

    var detector: DetectorClient? {
        guard let api else { return nil }
        return DetectorClient(baseURL: settings.detectorBaseURL, token: api.token)
    }

    // MARK: Session

    func start() async {
        userToken = Keychain.string(StorageKey.userToken)
        server = Keychain.codable(PlexServer.self, StorageKey.server)
        guard userToken != nil else {
            phase = .login
            return
        }
        if let server {
            await connect(server)
        } else {
            await loadServers()
        }
    }

    func didLogin(token: String) async {
        userToken = token
        Keychain.setString(token, for: StorageKey.userToken)
        await loadServers()
    }

    func loadServers() async {
        guard let userToken else {
            phase = .login
            return
        }
        phase = .connecting("Ищу серверы…")
        do {
            let servers = try await account.servers(token: userToken)
            if servers.count == 1, let only = servers.first {
                await choose(only)
            } else {
                phase = .choosingServer(servers)
            }
        } catch HTTPError.status(401) {
            logout()
        } catch {
            phase = .failed("Не удалось получить список серверов: \(error.localizedDescription)")
        }
    }

    func choose(_ server: PlexServer) async {
        self.server = server
        Keychain.setCodable(server, for: StorageKey.server)
        await connect(server)
    }

    func connect(_ server: PlexServer) async {
        phase = .connecting("Подключаюсь к «\(server.name)»…")
        var candidates = server.candidateURLs
        if let preferred = URL(string: settings.preferredConnection), !settings.preferredConnection.isEmpty {
            candidates.removeAll { $0 == preferred }
            candidates.insert(preferred, at: 0)
        }
        guard let url = await PlexServerAPI.firstReachable(candidates, token: server.accessToken, client: clientInfo) else {
            // Server list may be stale (new address): refresh it once.
            if let userToken, let fresh = try? await account.servers(token: userToken).first(where: { $0.id == server.id }),
               fresh.candidateURLs != server.candidateURLs {
                self.server = fresh
                Keychain.setCodable(fresh, for: StorageKey.server)
                if let url = await PlexServerAPI.firstReachable(fresh.candidateURLs, token: fresh.accessToken, client: clientInfo) {
                    await finishConnecting(url: url, server: fresh)
                    return
                }
            }
            phase = .failed("Сервер «\(server.name)» недоступен. Проверьте, что он включён и Apple TV в той же сети.")
            return
        }
        await finishConnecting(url: url, server: server)
    }

    private func finishConnecting(url: URL, server: PlexServer) async {
        let api = PlexServerAPI(baseURL: url, token: server.accessToken, client: clientInfo)
        do {
            sections = try await api.sections().filter { $0.kind == .movie || $0.kind == .show }
            self.api = api
            phase = .ready
        } catch HTTPError.status(401) {
            logout()
        } catch {
            phase = .failed("Не удалось загрузить медиатеку: \(error.localizedDescription)")
        }
    }

    func retry() async {
        if let server {
            await connect(server)
        } else {
            await start()
        }
    }

    func switchServer() async {
        server = nil
        api = nil
        Keychain.set(nil, for: StorageKey.server)
        settings.preferredConnection = ""
        await loadServers()
    }

    func logout() {
        Keychain.set(nil, for: StorageKey.userToken)
        Keychain.set(nil, for: StorageKey.server)
        userToken = nil
        server = nil
        api = nil
        sections = []
        phase = .login
    }

    // MARK: Playback

    /// Asks "resume or restart" when the item is partially watched.
    func requestPlay(_ item: PlexItem) {
        if ResumePolicy.resumePosition(for: item) != nil {
            resumeCandidate = item
        } else {
            play(item, from: nil)
        }
    }

    func play(_ item: PlexItem, from position: Double?) {
        resumeCandidate = nil
        playback = PlaybackRequest(item: item, startAt: position)
    }

    func playbackEnded() {
        playback = nil
        refresh()
    }

    func refresh() {
        refreshID += 1
    }

    func setWatched(_ item: PlexItem, _ watched: Bool) async {
        guard let api else { return }
        do {
            if watched {
                try await api.markWatched(ratingKey: item.ratingKey)
            } else {
                try await api.markUnwatched(ratingKey: item.ratingKey)
            }
        } catch {
            print("watch state: \(error)")
        }
        refresh()
    }
}
