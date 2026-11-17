import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Identifies this app to plex.tv and the media server (`X-Plex-*` headers).
public struct PlexClientInfo: Sendable, Equatable {
    public var clientIdentifier: String
    public var product: String
    public var version: String
    public var platform: String
    public var platformVersion: String
    public var device: String
    public var deviceName: String

    public init(
        clientIdentifier: String,
        product: String = "SkipTV",
        version: String = "1.0",
        platform: String = "tvOS",
        platformVersion: String = "",
        device: String = "Apple TV",
        deviceName: String = "SkipTV"
    ) {
        self.clientIdentifier = clientIdentifier
        self.product = product
        self.version = version
        self.platform = platform
        self.platformVersion = platformVersion
        self.device = device
        self.deviceName = deviceName
    }

    public var headers: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": platform,
            "X-Plex-Platform-Version": platformVersion,
            "X-Plex-Device": device,
            "X-Plex-Device-Name": deviceName,
            "X-Plex-Provides": "player",
            "Accept": "application/json",
        ]
    }

    func request(_ url: URL, method: String = "GET", token: String? = nil, timeout: TimeInterval = 15) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        return request
    }
}
