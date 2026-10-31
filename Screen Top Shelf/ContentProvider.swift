//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

#if DEBUG
import OSLog

private let topShelfDiagnosticsLogger = Logger(
    subsystem: "com.snowfin.tvos",
    category: "TopShelf"
)
#endif

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
        #if DEBUG
        topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Provider invoked")
        #endif

        guard let appGroupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
        else {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Provider cannot resolve the App Group container URL"
            )
            #endif
            return nil
        }

        #if DEBUG
        topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Provider App Group container URL resolved")
        #endif

        let directoryURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("TopShelf", isDirectory: true)
        let snapshotURL = directoryURL.appendingPathComponent("continue-watching.json")
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            #if DEBUG
            topShelfDiagnosticsLogger.error("[SCREEN_TOP_SHELF] Provider snapshot file is missing")
            #endif
            return nil
        }
        #if DEBUG
        topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Provider snapshot file exists")
        #endif

        let data: Data
        do {
            data = try Data(contentsOf: snapshotURL)
        } catch {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Provider snapshot read failed: \(Self.safeErrorDescription(error), privacy: .public)"
            )
            #endif
            return nil
        }

        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Provider snapshot decoding failed: \(Self.safeErrorDescription(error), privacy: .public)"
            )
            #endif
            return nil
        }

        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Provider decoded snapshot items=\(snapshot.items.count, privacy: .public)"
        )
        #endif

        var missingArtworkCount = 0
        let items = snapshot.items.compactMap { snapshotItem -> TVTopShelfSectionedItem? in
            let imageURL = directoryURL.appendingPathComponent(snapshotItem.imageFilename)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                missingArtworkCount += 1
                return nil
            }

            let item = TVTopShelfSectionedItem(identifier: snapshotItem.id)
            item.title = snapshotItem.title
            item.imageShape = .hdtv
            item.playbackProgress = min(max(snapshotItem.progress, 0), 1)
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            item.displayAction = TVTopShelfAction(url: snapshotItem.deepLink)
            item.playAction = TVTopShelfAction(url: snapshotItem.deepLink)
            return item
        }

        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Provider item validation complete valid=\(items.count, privacy: .public) missingArtwork=\(missingArtworkCount, privacy: .public)"
        )
        #endif
        guard !items.isEmpty else {
            #if DEBUG
            topShelfDiagnosticsLogger.error("[SCREEN_TOP_SHELF] Provider returning nil because no valid items remain")
            #endif
            return nil
        }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Continue Watching"
        #if DEBUG
        topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Provider returning valid Continue Watching content")
        #endif
        return TVTopShelfSectionedContent(sections: [section])
    }

    #if DEBUG
    private static func safeErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        let redactedDescription = nsError.localizedDescription
            .replacingOccurrences(
                of: #"(?i)(?:https?|swiftfin)://[^\s\"']+"#,
                with: "<redacted-url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b|\b[0-9a-fA-F]{24,}\b"#,
                with: "<redacted-id>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(api[_-]?key|access[_-]?token|token|authorization)=([^&\s]+)"#,
                with: "$1=<redacted>",
                options: .regularExpression
            )
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(redactedDescription)"
    }
    #endif
}
