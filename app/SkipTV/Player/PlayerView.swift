import SkipTVKit
import SwiftUI

struct PlayerScreen: View {
    @Environment(AppModel.self) private var app
    let request: PlaybackRequest
    /// Created once: each PlayerModel owns an mpv instance.
    @State private var model: PlayerModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerView(model: model) {
                    app.playbackEnded()
                }
            }
        }
        .onAppear {
            guard model == nil else { return }
            guard let api = app.api else {
                app.playbackEnded()
                return
            }
            model = PlayerModel(request: request, api: api, detector: app.detector, settings: app.settings)
        }
    }
}

private struct MPVVideoView: UIViewRepresentable {
    let player: MPVPlayer

    func makeUIView(context: Context) -> MPVLayerView {
        MPVLayerView(player: player)
    }

    func updateUIView(_ uiView: MPVLayerView, context: Context) {}
}

/// Invisible full-screen button that owns focus while nothing else is shown.
private struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct PlayerView: View {
    let model: PlayerModel
    var onClose: () -> Void

    enum Focus: Hashable {
        case surface, skip, nextPlay, nextCancel
    }

    @FocusState private var focus: Focus?

    var body: some View {
        ZStack {
            MPVVideoView(player: model.player)
                .ignoresSafeArea()

            Button {
                model.controlsVisible ? model.togglePause() : model.showControls()
            } label: {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(SurfaceButtonStyle())
            .focused($focus, equals: .surface)
            .ignoresSafeArea()
            .disabled(model.tracksPanelVisible)

            if model.isLoading || model.isBuffering {
                ProgressView()
                    .scaleEffect(1.6)
                    .allowsHitTesting(false)
            }

            if model.controlsVisible || model.isPaused {
                ControlsOverlay(model: model)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()
                    if let card = model.nextCard {
                        NextEpisodeCardView(card: card, model: model, focus: $focus)
                    } else if let prompt = model.skipPrompt {
                        Button {
                            model.performSkip()
                        } label: {
                            Label(prompt.title, systemImage: "forward.end.fill")
                        }
                        .buttonStyle(AccentButtonStyle())
                        .focused($focus, equals: .skip)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.trailing, 90)
                .padding(.bottom, model.controlsVisible ? 200 : 90)
            }

            if model.tracksPanelVisible {
                TracksPanel(model: model)
                    .focusSection()
                    .transition(.move(edge: .trailing))
            }

            if let error = model.errorMessage {
                ErrorView(message: error)
                    .background(Color.black.opacity(0.85))
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.25), value: model.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: model.skipPrompt)
        .animation(.easeInOut(duration: 0.25), value: model.nextCard)
        .animation(.easeInOut(duration: 0.25), value: model.tracksPanelVisible)
        .onPlayPauseCommand { model.togglePause() }
        .onMoveCommand { direction in
            guard !model.tracksPanelVisible, focus == .surface || focus == nil else {
                model.showControls()
                return
            }
            switch direction {
            case .left: model.seek(by: -10)
            case .right: model.seek(by: 30)
            case .down:
                model.tracksPanelVisible = true
                model.showControls()
            case .up: model.showControls()
            @unknown default: break
            }
        }
        .onExitCommand {
            if model.tracksPanelVisible {
                model.tracksPanelVisible = false
                focus = .surface
            } else if model.nextCard != nil {
                model.cancelNextEpisode()
            } else {
                model.close()
            }
        }
        .onChange(of: model.skipPrompt) { _, prompt in
            if model.nextCard == nil, !model.tracksPanelVisible {
                focus = prompt == nil ? .surface : .skip
            }
        }
        .onChange(of: model.nextCard?.item.ratingKey) { _, key in
            focus = key == nil ? (model.skipPrompt == nil ? .surface : .skip) : .nextPlay
        }
        .onChange(of: model.tracksPanelVisible) { _, visible in
            // The surface is disabled while the panel is open, so focus moves into the panel.
            focus = visible ? nil : .surface
        }
        .onChange(of: model.finished) { _, finished in
            if finished { onClose() }
        }
        .onAppear {
            focus = .surface
            model.start()
        }
        .onDisappear { model.close() }
        .persistentSystemOverlays(.hidden)
    }
}

private struct ControlsOverlay: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.item.displayTitle)
                    .font(.system(size: 44, weight: .bold))
                if let subtitle = model.item.type == .episode ? model.item.displaySubtitle : model.item.year.map(String.init) {
                    Text(subtitle)
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            VStack(spacing: 14) {
                ScrubBar(position: model.position, duration: model.duration, segments: model.segments)
                HStack {
                    Image(systemName: model.isPaused ? "pause.fill" : "play.fill")
                    Text(TimeFormat.clock(model.position))
                    Spacer()
                    Text("◀ −10 с   ▶ +30 с   ▼ дорожки")
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("−" + TimeFormat.clock(max(0, model.duration - model.position)))
                }
                .font(.system(size: 24, weight: .medium).monospacedDigit())
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.8)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct ScrubBar: View {
    let position: Double
    let duration: Double
    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if duration > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: max(3, width * segment.length / duration))
                            .offset(x: width * segment.start / duration)
                    }
                }
                Capsule().fill(Theme.accent).frame(width: width * fraction)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .offset(x: width * fraction - 11)
            }
        }
        .frame(height: 10)
    }
}

private struct NextEpisodeCardView: View {
    @Environment(AppModel.self) private var app
    let card: PlayerModel.NextEpisodeCard
    let model: PlayerModel
    var focus: FocusState<PlayerView.Focus?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            RemoteImage(url: app.api?.imageURL(card.item.landscapePath, width: 640, height: 360))
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text(card.secondsLeft.map { "Следующая серия через \($0)" } ?? "Следующая серия")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(card.item.displaySubtitle ?? card.item.title)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 20) {
                    Button {
                        model.playNext()
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                    .buttonStyle(AccentButtonStyle())
                    .focused(focus, equals: .nextPlay)

                    Button("Титры") {
                        model.cancelNextEpisode()
                    }
                    .buttonStyle(AccentButtonStyle())
                    .focused(focus, equals: .nextCancel)
                }
            }
            .frame(width: 560, alignment: .leading)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct TracksPanel: View {
    let model: PlayerModel

    var body: some View {
        HStack {
            Spacer()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header("Аудио")
                    if model.audioTracks.isEmpty {
                        Text("Нет дорожек").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(model.audioTracks) { track in
                        row(track.displayName, selected: model.selectedAudio == track.id) {
                            model.selectAudio(track)
                        }
                    }
                    header("Субтитры").padding(.top, 30)
                    row("Выключены", selected: model.selectedSubtitle == nil) {
                        model.selectSubtitle(nil)
                    }
                    ForEach(model.subtitleTracks) { track in
                        row(track.displayName, selected: model.selectedSubtitle == track.id) {
                            model.selectSubtitle(track)
                        }
                    }
                }
                .padding(50)
            }
            .frame(width: 760)
            .background(.regularMaterial)
        }
        .ignoresSafeArea()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Theme.secondaryText)
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .font(.system(size: 26))
            .frame(maxWidth: .infinity)
        }
    }
}
