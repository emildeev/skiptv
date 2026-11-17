import SkipTVKit
import SwiftUI

@main
struct SkipTVApp: App {
    @State private var app = AppModel()

    init() {
        // Posters and backdrops are cached on disk between launches.
        URLCache.shared = URLCache(memoryCapacity: 128 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.phase {
            case .starting:
                LoadingView(text: "SkipTV")
            case .login:
                LoginView()
            case .choosingServer(let servers):
                ServerPickerView(servers: servers)
            case .connecting(let text):
                LoadingView(text: text)
            case .failed(let message):
                ConnectionErrorView(message: message)
            case .ready:
                MainTabs()
            }
        }
        .pageBackground()
        .task { await app.start() }
        .fullScreenCover(item: $app.playback) { request in
            PlayerScreen(request: request)
                .environment(app)
        }
        .confirmationDialog(
            app.resumeCandidate?.displayTitle ?? "",
            isPresented: Binding(
                get: { app.resumeCandidate != nil },
                set: { if !$0 { app.resumeCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: app.resumeCandidate
        ) { item in
            if let position = ResumePolicy.resumePosition(for: item) {
                Button("Продолжить с \(TimeFormat.clock(position))") { app.play(item, from: position) }
            }
            Button("С начала") { app.play(item, from: nil) }
            Button("Отмена", role: .cancel) { app.resumeCandidate = nil }
        } message: { item in
            if let subtitle = item.displaySubtitle { Text(subtitle) }
        }
    }
}

private struct ConnectionErrorView: View {
    @Environment(AppModel.self) private var app
    let message: String

    var body: some View {
        VStack(spacing: 40) {
            ErrorView(message: message)
                .frame(maxHeight: 400)
            HStack(spacing: 30) {
                Button("Повторить") { Task { await app.retry() } }
                Button("Выбрать сервер") { Task { await app.switchServer() } }
                Button("Выйти", role: .destructive) { app.logout() }
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            TabStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "house") }
            ForEach(app.sections) { section in
                TabStack { LibraryView(section: section) }
                    .tabItem { Label(section.title, systemImage: section.kind == .movie ? "film" : "tv") }
            }
            TabStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
