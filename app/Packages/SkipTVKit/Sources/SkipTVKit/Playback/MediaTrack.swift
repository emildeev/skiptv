import Foundation

/// Audio or subtitle track as reported by the player (mpv `track-list`).
public struct MediaTrack: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case audio, subtitle = "sub", video
    }

    /// Player track id (mpv `aid`/`sid`).
    public var id: Int
    public var kind: Kind
    public var language: String?
    public var title: String?
    public var codec: String?
    public var channels: Int?
    public var isDefault: Bool
    public var isForced: Bool
    public var isExternal: Bool

    public init(
        id: Int,
        kind: Kind,
        language: String? = nil,
        title: String? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isExternal: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.language = language
        self.title = title
        self.codec = codec
        self.channels = channels
        self.isDefault = isDefault
        self.isForced = isForced
        self.isExternal = isExternal
    }

    public var isRussian: Bool { Language.isRussian(language) }

    /// "Русский · DTS-HD MA 5.1 · Дубляж"
    public var displayName: String {
        var parts: [String] = [Language.name(for: language) ?? "Дорожка \(id)"]
        if let codec, kind == .audio {
            var c = Self.codecName(codec)
            if let channels { c += " " + Self.channelLayout(channels) }
            parts.append(c)
        } else if let codec, kind == .subtitle {
            parts.append(Self.codecName(codec))
        }
        if let title, !title.isEmpty, title.lowercased() != (Language.name(for: language) ?? "").lowercased() {
            parts.append(title)
        }
        if isForced { parts.append("форсированные") }
        return parts.joined(separator: " · ")
    }

    static func codecName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "truehd": return "TrueHD"
        case "eac3": return "E-AC3"
        case "ac3": return "AC3"
        case "dts": return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "mp3": return "MP3"
        case "subrip", "srt": return "SRT"
        case "hdmv_pgs_subtitle", "pgs", "pgssub": return "PGS"
        case "ass", "ssa": return "ASS"
        case "dvd_subtitle", "vobsub": return "VobSub"
        case "webvtt": return "WebVTT"
        case "mov_text": return "Text"
        default: return codec.uppercased()
        }
    }

    static func channelLayout(_ channels: Int) -> String {
        switch channels {
        case 1: return "1.0"
        case 2: return "2.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }
}

public enum Language {
    static let russian: Set<String> = ["ru", "rus", "russian", "ru-ru"]

    public static func isRussian(_ code: String?) -> Bool {
        guard let code else { return false }
        return russian.contains(code.lowercased())
    }

    private static let names: [String: String] = [
        "ru": "Русский", "rus": "Русский",
        "en": "Английский", "eng": "Английский",
        "uk": "Украинский", "ukr": "Украинский",
        "ja": "Японский", "jpn": "Японский",
        "ko": "Корейский", "kor": "Корейский",
        "de": "Немецкий", "ger": "Немецкий", "deu": "Немецкий",
        "fr": "Французский", "fre": "Французский", "fra": "Французский",
        "es": "Испанский", "spa": "Испанский",
        "it": "Итальянский", "ita": "Итальянский",
        "zh": "Китайский", "chi": "Китайский", "zho": "Китайский",
        "tr": "Турецкий", "tur": "Турецкий",
        "pl": "Польский", "pol": "Польский",
        "pt": "Португальский", "por": "Португальский",
    ]

    public static func name(for code: String?) -> String? {
        guard let code, !code.isEmpty, code.lowercased() != "und" else { return nil }
        return names[code.lowercased()] ?? code
    }
}

public enum TrackSelector {
    /// Russian audio first; otherwise what the file marks as default; otherwise the first.
    public static func defaultAudio(_ tracks: [MediaTrack]) -> MediaTrack? {
        let audio = tracks.filter { $0.kind == .audio }
        let russian = audio.filter(\.isRussian)
        // Several Russian dubs: prefer the file default among them, then the first.
        return russian.first(where: \.isDefault) ?? russian.first
            ?? audio.first(where: \.isDefault) ?? audio.first
    }

    /// With Russian audio: only forced Russian subtitles (signs, foreign speech).
    /// Without Russian audio: full Russian subtitles if present.
    public static func defaultSubtitle(_ tracks: [MediaTrack], audio: MediaTrack?) -> MediaTrack? {
        let subs = tracks.filter { $0.kind == .subtitle && $0.isRussian }
        if audio?.isRussian == true {
            return subs.first(where: \.isForced)
        }
        return subs.first(where: { !$0.isForced }) ?? subs.first
    }
}
