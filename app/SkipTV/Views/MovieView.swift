import SkipTVKit
import SwiftUI

struct MovieView: View {
    @Environment(AppModel.self) private var app
    let initial: PlexItem

    @State private var movie: PlexItem?

    private var item: PlexItem { movie ?? initial }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(url: app.api?.imageURL(item.art, width: 1920, height: 1080))

            HStack(alignment: .top, spacing: 70) {
                RemoteImage(url: app.api?.imageURL(item.thumb, width: 600, height: 900))
                    .frame(width: 400, height: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 20)

                VStack(alignment: .leading, spacing: 22) {
                    Text(item.title)
                        .font(.system(size: 68, weight: .heavy))
                        .lineLimit(2)
                    HStack(spacing: 18) {
                        if let year = item.year { Text(String(year)) }
                        if let runtime = TimeFormat.runtime(milliseconds: item.duration) { Text(runtime) }
                        if let rating = item.contentRating { Text(rating) }
                        if let score = item.audienceRating { Text(String(format: "★ %.1f", score)) }
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 20, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.secondaryText, lineWidth: 2))
                        }
                        if item.isWatched {
                            Label("Просмотрено", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.watched)
                        }
                    }
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)

                    Text(item.summary ?? "")
                        .font(.system(size: 26))
                        .lineLimit(7)
                        .frame(maxWidth: 1100, alignment: .leading)

                    HStack(spacing: 24) {
                        if let position = ResumePolicy.resumePosition(for: item) {
                            Button {
                                app.play(item, from: position)
                            } label: {
                                Label("Продолжить с \(TimeFormat.clock(position))", systemImage: "play.fill")
                            }
                            Button {
                                app.play(item, from: nil)
                            } label: {
                                Label("С начала", systemImage: "arrow.counterclockwise")
                            }
                        } else {
                            Button {
                                app.play(item, from: nil)
                            } label: {
                                Label("Смотреть", systemImage: "play.fill")
                            }
                        }
                        Button {
                            Task { await app.setWatched(item, !item.isWatched) }
                        } label: {
                            Label(item.isWatched ? "Не просмотрено" : "Просмотрено", systemImage: item.isWatched ? "eye.slash" : "checkmark")
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, Theme.pageInset)
            .padding(.top, 80)
        }
        .task(id: app.refreshID) {
            movie = try? await app.api?.item(ratingKey: initial.ratingKey)
        }
    }

    private var badges: [String] {
        guard let media = item.media.first else { return [] }
        var result: [String] = []
        if media.videoResolution?.lowercased() == "4k" { result.append("4K") }
        if let range = media.dynamicRangeBadge { result.append(range) }
        return result
    }
}
