import CoreImage.CIFilterBuiltins
import SkipTVKit
import SwiftUI

/// Sign in with a plex.tv PIN: the user types the code at plex.tv/link.
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var pin: PlexPin?
    @State private var error: String?

    var body: some View {
        HStack(spacing: 120) {
            VStack(alignment: .leading, spacing: 36) {
                Text("SkipTV")
                    .font(.system(size: 76, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                Text("Войдите через аккаунт Plex")
                    .font(.system(size: 40, weight: .semibold))
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Откройте **\(PlexAccountAPI.linkURL)** на телефоне или компьютере")
                    step(2, "Войдите в аккаунт Plex")
                    step(3, "Введите код справа")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("Повторить") { Task { await run() } }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)

            VStack(spacing: 40) {
                Text(pin?.code ?? "····")
                    .font(.system(size: 120, weight: .bold, design: .monospaced))
                    .kerning(16)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 24)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
                if let qr = QRCode.image(for: "https://\(PlexAccountAPI.linkURL)") {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 260, height: 260)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text("\(number)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.system(size: 30))
        }
    }

    /// Creates a PIN and polls it until linked; renews expired PINs.
    private func run() async {
        error = nil
        while !Task.isCancelled {
            do {
                let created = try await app.account.createPin()
                pin = created
                let deadline = Date().addingTimeInterval(TimeInterval(created.expiresIn ?? 900) - 10)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    let checked = try await app.account.checkPin(id: created.id)
                    if let token = checked.authToken, !token.isEmpty {
                        await app.didLogin(token: token)
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = "Не удалось связаться с plex.tv: \(error.localizedDescription)"
                return
            }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct ServerPickerView: View {
    @Environment(AppModel.self) private var app
    let servers: [PlexServer]

    var body: some View {
        VStack(spacing: 40) {
            Text("Выберите сервер")
                .font(.system(size: 48, weight: .bold))
            if servers.isEmpty {
                Text("В аккаунте нет доступных серверов Plex.")
                    .foregroundStyle(Theme.secondaryText)
                Button("Обновить") { Task { await app.loadServers() } }
                Button("Выйти", role: .destructive) { app.logout() }
            }
            ForEach(servers) { server in
                Button {
                    Task { await app.choose(server) }
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                        Text(server.name)
                        Spacer()
                        if server.owned { Text("Мой").foregroundStyle(Theme.secondaryText) }
                    }
                    .frame(width: 800)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
