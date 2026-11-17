import Foundation
import Libmpv
import SkipTVKit
import UIKit

/// Events delivered on the main thread.
@MainActor
protocol MPVPlayerDelegate: AnyObject {
    func mpvTimeChanged(_ position: Double)
    func mpvDurationChanged(_ duration: Double)
    func mpvPauseChanged(_ paused: Bool)
    func mpvBufferingChanged(_ buffering: Bool)
    func mpvFileLoaded()
    func mpvSeekFinished()
    func mpvReachedEnd()
    func mpvFailed(_ message: String)
}

/// CAMetalLayer that ignores MoltenVK's 1x1 drawable size resets
/// (https://github.com/mpv-player/mpv/pull/13651).
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

struct MPVOptions {
    /// Lighter rendering profile for weak devices / 4K at high frame rates.
    var fastRendering = false
}

/// Thin wrapper over libmpv rendering into a Metal layer (gpu-next + MoltenVK).
/// Must be shut down with `shutdown()`; until then it retains itself for the event callback.
final class MPVPlayer {
    let layer = MPVMetalLayer()
    weak var delegate: MPVPlayerDelegate?

    private var mpv: OpaquePointer?
    private let queue = DispatchQueue(label: "skiptv.mpv", qos: .userInitiated)
    private var retainedSelf: Unmanaged<MPVPlayer>?

    private enum Property {
        static let timePos = "time-pos"
        static let duration = "duration"
        static let pause = "pause"
        static let pausedForCache = "paused-for-cache"
        static let eofReached = "eof-reached"
    }

    init(options: MPVOptions) {
        layer.framebufferOnly = true
        layer.backgroundColor = UIColor.black.cgColor
        layer.contentsScale = UIScreen.main.nativeScale
        setup(options)
    }

    private func setup(_ options: MPVOptions) {
        guard let handle = mpv_create() else {
            return
        }
        mpv = handle

        // mpv takes the CAMetalLayer pointer as an int64 "window id".
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid))
        set("vo", "gpu-next")
        set("gpu-api", "vulkan")
        set("gpu-context", "moltenvk")
        set("hwdec", "videotoolbox")
        set("video-rotate", "no")
        if options.fastRendering {
            set("profile", "fast")
        }
        // We drive end of playback ourselves (next episode card).
        set("keep-open", "yes")
        set("load-scripts", "no")
        set("ytdl", "no")
        set("osd-level", "0")
        set("input-default-bindings", "no")
        set("input-vo-keyboard", "no")
        // Network cache for 4K remuxes over Wi-Fi.
        set("cache", "yes")
        set("demuxer-max-bytes", "300MiB")
        set("demuxer-max-back-bytes", "64MiB")
        set("demuxer-readahead-secs", "30")
        set("network-timeout", "30")
        set("user-agent", "SkipTV")
        // Tracks are chosen by TrackSelector after load; these are just fallbacks.
        set("alang", "ru,rus,russian")
        set("slang", "no")
        set("subs-fallback", "no")
        set("sub-auto", "no")
        set("hr-seek", "yes")
#if DEBUG
        check(mpv_request_log_messages(handle, "warn"))
#else
        check(mpv_request_log_messages(handle, "error"))
#endif

        check(mpv_initialize(handle))

        mpv_observe_property(handle, 0, Property.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, Property.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, Property.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, Property.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, Property.eofReached, MPV_FORMAT_FLAG)

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue()
            player.drainEvents()
        }, retained.toOpaque())
    }

    // MARK: Commands

    func load(_ url: URL, start: Double?) {
        // `start` applies to the next loaded file.
        if let start, start > 0 {
            setProperty("start", String(format: "%.3f", start))
        } else {
            setProperty("start", "none")
        }
        command(["loadfile", url.absoluteString, "replace"])
    }

    func play() { setFlag(Property.pause, false) }
    func pause() { setFlag(Property.pause, true) }

    func seek(to seconds: Double) {
        command(["seek", String(format: "%.3f", max(0, seconds)), "absolute+exact"])
    }

    func seek(by seconds: Double) {
        command(["seek", String(format: "%.3f", seconds), "relative+exact"])
    }

    /// Adds an external subtitle file without selecting it.
    func addSubtitle(_ url: URL, title: String?, language: String?) {
        command(["sub-add", url.absoluteString, "auto", title ?? "", language ?? ""])
    }

    func selectAudio(_ id: Int?) {
        setProperty("aid", id.map(String.init) ?? "no")
    }

    func selectSubtitle(_ id: Int?) {
        setProperty("sid", id.map(String.init) ?? "no")
    }

    /// Video goes off while the app is in the background, to avoid a black screen on return.
    func setVideoEnabled(_ enabled: Bool) {
        setProperty("vid", enabled ? "auto" : "no")
    }

    var currentAudioID: Int? { Int(getString("aid") ?? "") }
    var currentSubtitleID: Int? { Int(getString("sid") ?? "") }

    /// Audio and subtitle tracks of the loaded file.
    func tracks() -> [MediaTrack] {
        let count = getInt("track-list/count") ?? 0
        var result: [MediaTrack] = []
        for i in 0..<count {
            let prefix = "track-list/\(i)/"
            guard let typeName = getString(prefix + "type"),
                  let kind = MediaTrack.Kind(rawValue: typeName),
                  kind != .video,
                  let id = getInt(prefix + "id") else { continue }
            result.append(MediaTrack(
                id: id,
                kind: kind,
                language: getString(prefix + "lang"),
                title: getString(prefix + "title"),
                codec: getString(prefix + "codec"),
                channels: getInt(prefix + "demux-channel-count"),
                isDefault: getFlag(prefix + "default"),
                isForced: getFlag(prefix + "forced"),
                isExternal: getFlag(prefix + "external")
            ))
        }
        return result
    }

    func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        let retained = retainedSelf
        retainedSelf = nil
        queue.async {
            mpv_terminate_destroy(handle)
            retained?.release()
        }
    }

    // MARK: Events

    private func drainEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let handle = self.mpv {
                guard let event = mpv_wait_event(handle, 0) else { break }
                let id = event.pointee.event_id
                if id == MPV_EVENT_NONE { break }
                self.handle(event.pointee)
                if id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }

    private func handle(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            guard let name = property.name.map({ String(cString: $0) }), let value = property.data else { return }
            switch (name, property.format) {
            case (Property.timePos, MPV_FORMAT_DOUBLE):
                let seconds = value.assumingMemoryBound(to: Double.self).pointee
                main { $0.mpvTimeChanged(seconds) }
            case (Property.duration, MPV_FORMAT_DOUBLE):
                let seconds = value.assumingMemoryBound(to: Double.self).pointee
                main { $0.mpvDurationChanged(seconds) }
            case (Property.pause, MPV_FORMAT_FLAG):
                let flag = value.assumingMemoryBound(to: Int32.self).pointee != 0
                main { $0.mpvPauseChanged(flag) }
            case (Property.pausedForCache, MPV_FORMAT_FLAG):
                let flag = value.assumingMemoryBound(to: Int32.self).pointee != 0
                main { $0.mpvBufferingChanged(flag) }
            case (Property.eofReached, MPV_FORMAT_FLAG):
                if value.assumingMemoryBound(to: Int32.self).pointee != 0 {
                    main { $0.mpvReachedEnd() }
                }
            default:
                break
            }
        case MPV_EVENT_FILE_LOADED:
            main { $0.mpvFileLoaded() }
        case MPV_EVENT_PLAYBACK_RESTART:
            main { $0.mpvSeekFinished() }
        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return }
            let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            if end.reason == MPV_END_FILE_REASON_ERROR {
                let message = String(cString: mpv_error_string(end.error))
                main { $0.mpvFailed(message) }
            }
        case MPV_EVENT_LOG_MESSAGE:
            guard let data = event.data else { return }
            let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            print("[mpv/\(String(cString: message.prefix))] \(String(cString: message.level)): \(String(cString: message.text))", terminator: "")
        default:
            break
        }
    }

    private func main(_ body: @escaping @MainActor (MPVPlayerDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let delegate = self?.delegate else { return }
                body(delegate)
            }
        }
    }

    // MARK: libmpv helpers

    private func set(_ name: String, _ value: String) {
        guard let mpv else { return }
        check(mpv_set_option_string(mpv, name, value))
    }

    private func setProperty(_ name: String, _ value: String) {
        guard let mpv else { return }
        check(mpv_set_property_string(mpv, name, value))
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int32 = flag ? 1 : 0
        check(mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data))
    }

    private func getString(_ name: String) -> String? {
        guard let mpv, let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private func getInt(_ name: String) -> Int? {
        guard let mpv else { return nil }
        var data: Int64 = 0
        guard mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data) >= 0 else { return nil }
        return Int(data)
    }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data: Int32 = 0
        guard mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data) >= 0 else { return false }
        return data != 0
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer {
            for pointer in cArgs where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
        check(mpv_command(mpv, &cArgs))
    }

    @discardableResult
    private func check(_ status: Int32) -> Bool {
        if status < 0 {
            print("[mpv] API error: \(String(cString: mpv_error_string(status)))")
            return false
        }
        return true
    }
}

/// Hosts the player's Metal layer.
final class MPVLayerView: UIView {
    let player: MPVPlayer

    init(player: MPVPlayer) {
        self.player = player
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(player.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.layer.frame = bounds
        CATransaction.commit()
    }
}
