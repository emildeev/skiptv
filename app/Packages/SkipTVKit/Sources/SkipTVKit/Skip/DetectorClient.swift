import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SegmentType: String, Codable, Sendable, CaseIterable {
    case intro, credits, recap, preview
}

/// A detected part of a media file; times are seconds from the file start.
public struct Segment: Codable, Hashable, Sendable {
    public var type: SegmentType
    public var start: Double
    public var end: Double

    public init(type: SegmentType, start: Double, end: Double) {
        self.type = type
        self.start = start
        self.end = end
    }

    public var length: Double { end - start }

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

public struct SegmentsResponse: Decodable, Sendable {
    public var ratingKey: String
    public var segments: [Segment]
    public var analyzed: Bool

    enum CodingKeys: String, CodingKey {
        case ratingKey, segments, analyzed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = c.lossyString(.ratingKey) ?? ""
        analyzed = (try? c.decodeIfPresent(Bool.self, forKey: .analyzed)) ?? false
        // Unknown segment types from a newer detector are dropped, not fatal.
        let raw = (try? c.decodeIfPresent([LossySegment].self, forKey: .segments)) ?? []
        segments = raw.compactMap(\.segment)
    }
}

/// Batch response: `{"items":[...]}` (what the detector serves) or a bare array.
struct SegmentsBatch: Decodable {
    var items: [SegmentsResponse]

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([SegmentsResponse].self) {
            items = array
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([SegmentsResponse].self, forKey: .items) ?? []
    }
}

private struct LossySegment: Decodable {
    var segment: Segment?

    init(from decoder: Decoder) throws {
        segment = try? Segment(from: decoder)
    }
}

/// Client of the SkipTV detector service. Never throws: when the detector is
/// down or knows nothing about the item, playback simply has no segments.
public struct DetectorClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://skiptv.emill.keenetic.pro")!

    public let baseURL: URL
    public let token: String
    public let transport: HTTPTransport
    public let timeout: TimeInterval

    public init(baseURL: URL, token: String, transport: HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 4) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
        self.timeout = timeout
    }

    public func segments(ratingKey: String) async -> [Segment] {
        guard let url = baseURL.appendingPlexPath("/v1/segments/\(ratingKey.strictQueryEncoded)") else { return [] }
        do {
            let response = try await transport.decode(SegmentsResponse.self, from: request(url))
            return Self.sanitize(response.segments)
        } catch {
            return []
        }
    }

    public func segments(ratingKeys: [String]) async -> [String: [Segment]] {
        guard !ratingKeys.isEmpty,
              let url = baseURL.appendingPlexPath("/v1/segments", query: [
                  URLQueryItem(name: "ratingKeys", value: ratingKeys.joined(separator: ",")),
              ]) else { return [:] }
        do {
            let batch = try await transport.decode(SegmentsBatch.self, from: request(url))
            var result: [String: [Segment]] = [:]
            for response in batch.items {
                result[response.ratingKey] = Self.sanitize(response.segments)
            }
            return result
        } catch {
            return [:]
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Drops broken segments and sorts by start time.
    static func sanitize(_ segments: [Segment]) -> [Segment] {
        segments
            .filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }
}
