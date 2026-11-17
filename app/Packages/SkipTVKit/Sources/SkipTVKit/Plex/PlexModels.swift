import Foundation

/// Top-level wrapper of every Plex Media Server JSON response.
public struct PlexResponse<Content: Decodable>: Decodable {
    public let mediaContainer: Content

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

public struct MetadataContainer: Decodable, Sendable {
    public var size: Int
    public var metadata: [PlexItem]

    enum CodingKeys: String, CodingKey {
        case size, metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try c.decodeIfPresent([PlexItem].self, forKey: .metadata) ?? []
        size = c.lossyInt(.size) ?? metadata.count
    }
}

public struct DirectoryContainer: Decodable, Sendable {
    public var directories: [PlexLibrarySection]

    enum CodingKeys: String, CodingKey {
        case directories = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        directories = try c.decodeIfPresent([PlexLibrarySection].self, forKey: .directories) ?? []
    }
}

public struct PlexLibrarySection: Decodable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case movie, show, artist, photo, other
    }

    public var key: String
    public var title: String
    public var type: String

    public var id: String { key }
    public var kind: Kind { Kind(rawValue: type) ?? .other }

    public init(key: String, title: String, type: String) {
        self.key = key
        self.title = title
        self.type = type
    }
}

public enum PlexItemType: String, Sendable, Codable {
    case movie, show, season, episode, clip, other
}

/// A Plex metadata item: movie, show, season or episode.
public struct PlexItem: Decodable, Hashable, Identifiable, Sendable {
    public var ratingKey: String
    public var key: String
    public var type: PlexItemType
    public var title: String
    public var summary: String?
    public var year: Int?
    public var index: Int?
    public var parentIndex: Int?
    public var parentRatingKey: String?
    public var parentTitle: String?
    public var grandparentRatingKey: String?
    public var grandparentTitle: String?
    public var thumb: String?
    public var art: String?
    public var parentThumb: String?
    public var grandparentThumb: String?
    public var grandparentArt: String?
    public var contentRating: String?
    public var audienceRating: Double?
    public var originallyAvailableAt: String?
    /// Milliseconds.
    public var duration: Int?
    /// Milliseconds, present when partially watched.
    public var viewOffset: Int?
    public var viewCount: Int?
    public var leafCount: Int?
    public var viewedLeafCount: Int?
    public var childCount: Int?
    public var addedAt: Int?
    public var media: [PlexMedia]

    public var id: String { ratingKey }

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, summary, year, index, parentIndex
        case parentRatingKey, parentTitle, grandparentRatingKey, grandparentTitle
        case thumb, art, parentThumb, grandparentThumb, grandparentArt
        case contentRating, audienceRating, originallyAvailableAt
        case duration, viewOffset, viewCount, leafCount, viewedLeafCount, childCount, addedAt
        case media = "Media"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = c.lossyString(.ratingKey) ?? ""
        key = c.lossyString(.key) ?? "/library/metadata/\(ratingKey)"
        type = PlexItemType(rawValue: c.lossyString(.type) ?? "") ?? .other
        title = c.lossyString(.title) ?? ""
        summary = c.lossyString(.summary)
        year = c.lossyInt(.year)
        index = c.lossyInt(.index)
        parentIndex = c.lossyInt(.parentIndex)
        parentRatingKey = c.lossyString(.parentRatingKey)
        parentTitle = c.lossyString(.parentTitle)
        grandparentRatingKey = c.lossyString(.grandparentRatingKey)
        grandparentTitle = c.lossyString(.grandparentTitle)
        thumb = c.lossyString(.thumb)
        art = c.lossyString(.art)
        parentThumb = c.lossyString(.parentThumb)
        grandparentThumb = c.lossyString(.grandparentThumb)
        grandparentArt = c.lossyString(.grandparentArt)
        contentRating = c.lossyString(.contentRating)
        audienceRating = c.lossyDouble(.audienceRating)
        originallyAvailableAt = c.lossyString(.originallyAvailableAt)
        duration = c.lossyInt(.duration)
        viewOffset = c.lossyInt(.viewOffset)
        viewCount = c.lossyInt(.viewCount)
        leafCount = c.lossyInt(.leafCount)
        viewedLeafCount = c.lossyInt(.viewedLeafCount)
        childCount = c.lossyInt(.childCount)
        addedAt = c.lossyInt(.addedAt)
        media = (try? c.decodeIfPresent([PlexMedia].self, forKey: .media)) ?? []
    }

    public init(
        ratingKey: String,
        type: PlexItemType,
        title: String,
        index: Int? = nil,
        parentIndex: Int? = nil,
        grandparentRatingKey: String? = nil,
        duration: Int? = nil,
        viewOffset: Int? = nil,
        viewCount: Int? = nil,
        media: [PlexMedia] = []
    ) {
        self.ratingKey = ratingKey
        self.key = "/library/metadata/\(ratingKey)"
        self.type = type
        self.title = title
        self.index = index
        self.parentIndex = parentIndex
        self.grandparentRatingKey = grandparentRatingKey
        self.duration = duration
        self.viewOffset = viewOffset
        self.viewCount = viewCount
        self.media = media
    }

    // MARK: Derived

    public var isWatched: Bool {
        switch type {
        case .show, .season:
            if let leafCount, let viewedLeafCount, leafCount > 0 { return viewedLeafCount >= leafCount }
            return false
        default:
            return (viewCount ?? 0) > 0 && (viewOffset ?? 0) == 0
        }
    }

    /// 0...1 progress of a partially watched item, `nil` when not started.
    public var progress: Double? {
        guard let viewOffset, let duration, duration > 0, viewOffset > 0 else { return nil }
        return min(1, Double(viewOffset) / Double(duration))
    }

    public var unwatchedLeafCount: Int? {
        guard let leafCount else { return nil }
        return max(0, leafCount - (viewedLeafCount ?? 0))
    }

    /// First playable file part (direct play).
    public var primaryPart: PlexPart? { media.first?.parts.first }

    /// "S1 · E3" style label for episodes.
    public var episodeLabel: String? {
        guard type == .episode else { return nil }
        switch (parentIndex, index) {
        case let (s?, e?): return "S\(s) · E\(e)"
        case let (nil, e?): return "E\(e)"
        default: return nil
        }
    }

    /// Poster image: show poster for episodes/seasons when they have no own.
    public var posterPath: String? {
        switch type {
        case .episode: return grandparentThumb ?? parentThumb ?? thumb
        case .season: return thumb ?? parentThumb
        default: return thumb
        }
    }

    /// Landscape image: episode still, or backdrop for everything else.
    public var landscapePath: String? {
        switch type {
        case .episode: return thumb ?? art ?? grandparentArt
        default: return art ?? thumb
        }
    }

    public var backdropPath: String? {
        art ?? grandparentArt ?? thumb
    }

    /// The show this item belongs to (for episodes and seasons) or itself.
    public var showRatingKey: String? {
        switch type {
        case .show: return ratingKey
        case .season: return parentRatingKey
        case .episode: return grandparentRatingKey
        default: return nil
        }
    }

    public var displayTitle: String {
        switch type {
        case .episode: return grandparentTitle ?? title
        case .season: return parentTitle ?? title
        default: return title
        }
    }

    public var displaySubtitle: String? {
        switch type {
        case .episode:
            return [episodeLabel, title].compactMap { $0 }.joined(separator: " — ")
        case .season:
            return title
        default:
            return year.map(String.init)
        }
    }
}

public struct PlexMedia: Decodable, Hashable, Sendable {
    public var id: String
    public var duration: Int?
    public var container: String?
    public var videoCodec: String?
    public var videoResolution: String?
    public var audioCodec: String?
    public var audioChannels: Int?
    public var parts: [PlexPart]

    enum CodingKeys: String, CodingKey {
        case id, duration, container, videoCodec, videoResolution, audioCodec, audioChannels
        case parts = "Part"
    }

    /// "DOLBY VISION", "HDR" or nil, from the video stream.
    public var dynamicRangeBadge: String? {
        guard let video = parts.first?.streams.first(where: { $0.kind == .video }) else { return nil }
        if video.doviPresent { return "DOLBY VISION" }
        switch video.colorTrc?.lowercased() {
        case "smpte2084", "arib-std-b67": return "HDR"
        default: return nil
        }
    }

    public init(id: String, parts: [PlexPart]) {
        self.id = id
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossyString(.id) ?? ""
        duration = c.lossyInt(.duration)
        container = c.lossyString(.container)
        videoCodec = c.lossyString(.videoCodec)
        videoResolution = c.lossyString(.videoResolution)
        audioCodec = c.lossyString(.audioCodec)
        audioChannels = c.lossyInt(.audioChannels)
        parts = (try? c.decodeIfPresent([PlexPart].self, forKey: .parts)) ?? []
    }
}

public struct PlexPart: Decodable, Hashable, Sendable {
    public var id: String
    /// Server path of the file, e.g. `/library/parts/123/1699999999/file.mkv`.
    public var key: String
    public var duration: Int?
    public var size: Int64?
    public var container: String?
    public var streams: [PlexStream]

    enum CodingKeys: String, CodingKey {
        case id, key, duration, size, container
        case streams = "Stream"
    }

    public init(id: String, key: String, streams: [PlexStream] = []) {
        self.id = id
        self.key = key
        self.streams = streams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossyString(.id) ?? ""
        key = c.lossyString(.key) ?? ""
        duration = c.lossyInt(.duration)
        size = c.lossyInt(.size).map(Int64.init)
        container = c.lossyString(.container)
        streams = (try? c.decodeIfPresent([PlexStream].self, forKey: .streams)) ?? []
    }
}

public struct PlexStream: Decodable, Hashable, Sendable {
    public enum Kind: Int, Sendable {
        case video = 1, audio = 2, subtitle = 3
    }

    public var id: String
    public var streamType: Int
    public var index: Int?
    public var codec: String?
    public var languageCode: String?
    public var displayTitle: String?
    /// Sidecar subtitle path (external SRT etc.), absent for embedded streams.
    public var key: String?
    public var colorTrc: String?
    public var doviPresent: Bool

    public var kind: Kind? { Kind(rawValue: streamType) }

    enum CodingKeys: String, CodingKey {
        case id, streamType, index, codec, languageCode, displayTitle, key, colorTrc
        case doviPresent = "DOVIPresent"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossyString(.id) ?? ""
        streamType = c.lossyInt(.streamType) ?? 0
        index = c.lossyInt(.index)
        codec = c.lossyString(.codec)
        languageCode = c.lossyString(.languageCode)
        displayTitle = c.lossyString(.displayTitle)
        key = c.lossyString(.key)
        colorTrc = c.lossyString(.colorTrc)
        doviPresent = (c.lossyInt(.doviPresent) ?? 0) != 0
    }
}

// MARK: - Lossy decoding (Plex is inconsistent about numbers vs strings)

extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func lossyInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }

    func lossyDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}
