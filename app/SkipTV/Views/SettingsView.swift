import SkipTVKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("Пропуск заставок и титров", selection: $settings.skipMode) {
                    ForEach(SkipMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Пропуск")
            } footer: {
                Text(skipFooter(settings.skipMode))
            }

            Section("Следующая серия") {
                Toggle("Включать автоматически", isOn: $settings.autoplayNext)
                Picker("Обратный отсчёт", selection: $settings.nextEpisodeCountdown) {
                    ForEach(AppSettings.countdownOptions, id: \.self) { seconds in
                        Text("\(seconds) с").tag(seconds)
                    }
                }
            }

            Section {
                TextField("Адрес детектора", text: $settings.detectorURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                Button("Сбросить адрес детектора") {
                    settings.detectorURL = DetectorClient.defaultBaseURL.absoluteString
                }
            } header: {
                Text("Детектор заставок")
            } footer: {
                Text("Сервис, который находит заставки и титры. Если он недоступен, видео просто играет без пропуска.")
            }

            Section {
                Toggle("Облегчённая отрисовка", isOn: $settings.fastRendering)
            } header: {
                Text("Плеер")
            } footer: {
                Text("Попробуйте, если 4K-видео подтормаживает. Действует со следующего запуска видео.")
            }

            Section("Сервер") {
                LabeledContent("Сервер", value: app.server?.name ?? "—")
                LabeledContent("Подключение", value: app.api?.baseURL.absoluteString ?? "—")
                if let server = app.server {
                    Picker("Адрес", selection: $settings.preferredConnection) {
                        Text("Автоматически").tag("")
                        ForEach(server.candidateURLs, id: \.absoluteString) { url in
                            Text(url.absoluteString).tag(url.absoluteString)
                        }
                    }
                    Button("Переподключиться") { Task { await app.connect(server) } }
                }
                Button("Сменить сервер") { Task { await app.switchServer() } }
                Button("Выйти из аккаунта Plex", role: .destructive) { app.logout() }
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .frame(maxWidth: 1300)
        .frame(maxWidth: .infinity)
    }

    private func skipFooter(_ mode: SkipMode) -> String {
        switch mode {
        case .auto:
            return "Заставки и титры пропускаются сами. В первой серии сезона вместо этого показывается кнопка «Пропустить»."
        case .button:
            return "Во время заставки и титров показывается кнопка «Пропустить»."
        case .off:
            return "Ничего не пропускается."
        }
    }
}
