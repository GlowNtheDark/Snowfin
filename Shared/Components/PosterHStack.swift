//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import Nuke
import SwiftUI

enum PosterHStackMetrics {

    static let itemSpacing: CGFloat = {
        #if os(tvOS)
        40
        #else
        EdgeInsets.edgePadding / 2
        #endif
    }()
}

struct PosterHStack<
    Data: Collection
>: View where Data.Element: Poster, Data.Index == Int {

    @Environment(\.self)
    private var environment

    @State
    private var imagePrefetcher = ImagePrefetcher(
        pipeline: .Swiftfin.posters,
        destination: .memoryCache,
        maxConcurrentRequestCount: UIDevice.isTV ? 3 : 2
    )

    let elements: Data
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Data.Element, Namespace.ID) -> Void

    #if os(tvOS)
    private var homeTiles: [FocusCoordinator.HomeTile] {
        guard environment.homeTileCoordinator != nil, let groupID = environment.homeFocusGroup else { return [] }
        var seen = Set<String>()
        return elements.enumerated().compactMap { index, item in
            guard let tile = FocusCoordinator.HomeTile.make(poster: item, groupID: groupID, index: index),
                  seen.insert(tile.itemID).inserted else { return nil }
            return tile
        }
    }
    #endif

    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(
            columns: displayType == .landscape ? 5 : 7,
            rows: 1,
            columnTrailingInset: 0
        )
        #else
        if UIDevice.isPad {
            let minWidth: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    220
                case (.landscape, .medium):
                    300
                case (_, .small):
                    140
//                case (_, .medium):
                default:
                    200
                }
            }()

            return .minimumWidth(
                columnWidth: minWidth,
                rows: 1
            )
        } else {
            let columnCount: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    2
                case (.landscape, .medium):
                    1.5
                case (_, .small):
                    3
//                case (_, .medium):
                default:
                    2
                }
            }()

            return .grid(
                columns: columnCount,
                rows: 1,
                columnTrailingInset: 0
            )
        }
        #endif
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        EdgeInsets.edgePadding
        #endif
    }

    private func prefetchRequests(for elements: [Data.Element]) -> [ImageRequest] {
        elements.compactMap { element -> ImageRequest? in
            var resolvedEnvironment = element.resolveEnvironment(environment)

            if var viewContextEnvironment = resolvedEnvironment as? WithViewContext {
                viewContextEnvironment.viewContext.insert(.isThumb)
                resolvedEnvironment = viewContextEnvironment as! Data.Element.Environment
            }

            let url = element.imageSources(
                for: displayType,
                size: size,
                environment: resolvedEnvironment
            )
            .first?
            .url

            guard let url else { return nil }
            return ImageRequest(url: url)
        }
    }

    var body: some View {
        CollectionHStack(
            uniqueElements: elements,
            layout: layout
        ) { item in
            PosterButton(
                item: item,
                displayType: displayType,
                size: size
            ) { namespace in
                action(item, namespace)
            }
            #if os(tvOS)
            .environment(\.homeFocusTile, homeTiles.first { tile in
                FocusCoordinator.HomeTile.make(poster: item, groupID: tile.groupID, index: tile.index)?.itemID == tile.itemID
            })
            #endif
        }
        .clipsToBounds(false)
        .insets(horizontal: horizontalInset)
        .itemSpacing(PosterHStackMetrics.itemSpacing)
        .onPrefetchingElements { elements in
            imagePrefetcher.startPrefetching(
                with: prefetchRequests(for: elements)
            )
        }
        .onCancelPrefetchingElements { elements in
            imagePrefetcher.stopPrefetching(
                with: prefetchRequests(for: elements)
            )
        }
        .scrollBehavior(.continuousLeadingEdge)
        .withViewContext(.isThumb)
        #if os(tvOS)
            .preference(key: HomeFocusRowsKey.self, value: environment.homeTileCoordinator == nil ? [] : [
                HomeFocusRow(
                    groupID: environment.homeFocusGroup ?? "",
                    order: environment.homeFocusRowOrder,
                    revision: environment.homeFocusRevision,
                    tiles: homeTiles
                ),
            ])
        #endif
    }
}
