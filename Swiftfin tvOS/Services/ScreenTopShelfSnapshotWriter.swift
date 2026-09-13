//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Nuke
import TVServices
import UIKit

@MainActor
enum ScreenTopShelfSnapshotWriter {

    private struct Candidate: Sendable {
        let deepLink: URL
        let id: String
        let imageURL: URL
        let progress: Double
        let title: String
    }

    private struct Snapshot: Codable, Sendable {
        let items: [Item]

        struct Item: Codable, Sendable {
            let deepLink: URL
            let id: String
            let imageFilename: String
            let progress: Double
            let title: String
        }
    }

    private nonisolated static let appGroupIdentifier = "group.com.snowfin.tvos"
    private nonisolated static let directoryName = "TopShelf"
    private nonisolated static let snapshotFilename = "continue-watching.json"
    private static var updateTask: Task<Void, Never>?

    static func clear() {
        updateTask?.cancel()
        updateTask = nil

        Task.detached(priority: .utility) {
            guard let directoryURL = topShelfDirectoryURL() else { return }
            try? FileManager.default.removeItem(at: directoryURL)
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    static func update(items: [BaseItemDto]) {
        updateTask?.cancel()

        guard let session = Container.shared.currentUserSession() else {
            clear()
            return
        }

        let candidates = items.prefix(12).compactMap { item -> Candidate? in
            guard let id = item.id,
                  let imageURL = landscapeImageURL(for: item),
                  let deepLink = URL(string: "swiftfin://\(session.server.id)/\(session.user.id)/item/\(id)")
            else { return nil }

            let position = Double(item.userData?.playbackPositionTicks ?? 0)
            let duration = Double(item.runTimeTicks ?? 0)
            let progress = duration > 0 ? min(max(position / duration, 0), 1) : 0

            return Candidate(
                deepLink: deepLink,
                id: id,
                imageURL: imageURL,
                progress: progress,
                title: topShelfTitle(for: item)
            )
        }

        updateTask = Task.detached(priority: .utility) {
            await writeSnapshot(for: candidates)
        }
    }

    private static func topShelfTitle(for item: BaseItemDto) -> String {
        guard item.type == .episode else { return item.displayTitle }

        let seriesName = item.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeTitle = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeNumber: String? = {
            switch (item.parentIndexNumber, item.indexNumber) {
            case let (season?, episode?):
                "S\(season):E\(episode)"
            case let (nil, episode?):
                "E\(episode)"
            case let (season?, nil):
                "S\(season)"
            case (nil, nil):
                nil
            }
        }()
        let details = [episodeNumber, episodeTitle]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        // Sectioned Top Shelf items have one native title, with no subtitle API.
        // tvOS controls how the line break is displayed and truncated.
        let title = [seriesName, details]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return title.isEmpty ? item.displayTitle : title
    }

    private static func landscapeImageURL(for item: BaseItemDto) -> URL? {
        var environment = BaseItemDto.Environment.default
        environment.viewContext.insert(.isThumb)

        return item.imageSources(
            for: .landscape,
            size: .custom(width: 1816),
            environment: environment
        )
        .first?
        .url
    }

    private nonisolated static func topShelfDirectoryURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private nonisolated static func writeSnapshot(for candidates: [Candidate]) async {
        guard !Task.isCancelled,
              let directoryURL = topShelfDirectoryURL()
        else { return }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            var snapshotItems: [Snapshot.Item] = []

            for candidate in candidates {
                guard !Task.isCancelled else { return }

                let request = ImageRequest(url: candidate.imageURL)
                guard let image = try? await ImagePipeline.Swiftfin.posters.image(for: request),
                      let data = image.jpegData(compressionQuality: 0.9)
                else {
                    continue
                }

                let imageFilename = "\(candidate.id).jpg"
                try data.write(
                    to: directoryURL.appendingPathComponent(imageFilename),
                    options: .atomic
                )

                snapshotItems.append(
                    .init(
                        deepLink: candidate.deepLink,
                        id: candidate.id,
                        imageFilename: imageFilename,
                        progress: candidate.progress,
                        title: candidate.title
                    )
                )
            }

            guard !Task.isCancelled else { return }

            let snapshot = Snapshot(items: snapshotItems)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(
                to: directoryURL.appendingPathComponent(snapshotFilename),
                options: .atomic
            )

            let retainedFilenames = Set(snapshotItems.map(\.imageFilename) + [snapshotFilename])
            let existingURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            for url in existingURLs where !retainedFilenames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }

            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            return
        }
    }
}
