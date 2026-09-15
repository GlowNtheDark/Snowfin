//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {

    private struct Snapshot: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let deepLink: URL
            let id: String
            let imageFilename: String
            let progress: Double
            let title: String
        }
    }

    private static let appGroupIdentifier = "group.com.snowfin.tvos"

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let directoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("TopShelf", isDirectory: true),
            let data = try? Data(contentsOf: directoryURL.appendingPathComponent("continue-watching.json")),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }

        let items = snapshot.items.compactMap { snapshotItem -> TVTopShelfSectionedItem? in
            let imageURL = directoryURL.appendingPathComponent(snapshotItem.imageFilename)
            guard FileManager.default.fileExists(atPath: imageURL.path) else { return nil }

            let item = TVTopShelfSectionedItem(identifier: snapshotItem.id)
            item.title = snapshotItem.title
            item.imageShape = .hdtv
            item.playbackProgress = min(max(snapshotItem.progress, 0), 1)
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            item.displayAction = TVTopShelfAction(url: snapshotItem.deepLink)
            item.playAction = TVTopShelfAction(url: snapshotItem.deepLink)
            return item
        }

        guard !items.isEmpty else { return nil }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Continue Watching"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
