import SwiftUI

/// AsyncImage with a placeholder; HTTP caching comes from the shared URLCache.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder(icon: "photo")
            default:
                placeholder(icon: nil)
            }
        }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.surface, Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
