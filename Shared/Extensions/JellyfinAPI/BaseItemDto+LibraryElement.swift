//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: consolidate width constants

private let baseItemListLandscapeWidth: CGFloat = 110
private let baseItemListPortraitWidth: CGFloat = 60

extension BaseItemDto: LibraryElement {

    @MainActor
    func routeFromLibrarySelection(
        router: Router.Wrapper,
        in namespace: Namespace.ID,
        episodeRouteOriginContext: EpisodeRouteOriginContext?
    ) {
        #if os(tvOS)
        if type == .episode,
           let episodeRouteOriginContext,
           let id
        {
            router.route(
                to: .episode(
                    item: self,
                    origin: episodeRouteOriginContext.origin(groupID: "", itemID: id)
                ),
                in: namespace
            )
            return
        }
        #endif

        libraryDidSelectElement(router: router, in: namespace)
    }

    var supportedLibraryStyleOptions: LibraryStyleOptions {
        switch type {
        case .collectionFolder, .folder, .userView:
            return BaseItemKind.libraryStyleOptions(for: supportedItemTypes)
        default:
            break
        }

        return type.map { BaseItemKind.libraryStyleOptions(for: [$0]) } ?? .default
    }

    func libraryDidSelectElement(
        router: Router.Wrapper,
        in namespace: Namespace.ID
    ) {
        switch type {
        case .collectionFolder, .folder, .userView:
            router.route(
                to: .library(library: ItemLibrary(parent: self, filters: .default)),
                in: namespace
            )
        default:
            router.route(to: .item(item: self), in: namespace)
        }
    }

    @ViewBuilder
    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        switch libraryStyle.displayType {
        case .grid:
            BaseItemDtoLibraryGridElement(item: self, libraryStyle: libraryStyle)
        case .list:
            BaseItemDtoLibraryListElement(item: self, libraryStyle: libraryStyle)
        }
    }
}

private struct BaseItemDtoLibraryGridElement: View {

    @Environment(\.itemStateStore)
    private var itemStateStore

    @Namespace
    private var namespace

    @Router
    private var router

    @Environment(\.episodeRouteOriginContext)
    private var episodeRouteOriginContext

    #if os(tvOS)
    @Environment(\.episodeRouteTabID)
    private var episodeRouteTabID
    #endif

    let item: BaseItemDto
    let libraryStyle: LibraryStyle

    private var resolvedLibraryStyle: LibraryStyle {
        item.resolvedLibraryStyle(libraryStyle)
    }

    private var episodeRouteOrigin: EpisodeRouteIntent.Origin? {
        guard item.type == .episode,
              let itemID = item.id,
              let episodeRouteOriginContext
        else { return nil }

        return episodeRouteOriginContext.origin(groupID: "", itemID: itemID)
    }

    @ViewBuilder
    private var posterContent: some View {
        if let itemState = itemStateStore?.state(for: item) {
            ItemStatePoster(
                itemState: itemState,
                item: item,
                displayType: resolvedLibraryStyle.posterDisplayType,
                routeEpisodeOrigin: episodeRouteOrigin
            ) { updatedItem, namespace in
                updatedItem.routeFromLibrarySelection(
                    router: router,
                    in: namespace,
                    episodeRouteOriginContext: episodeRouteOriginContext
                )
            }
        } else {
            poster(for: item)
        }
    }

    @ViewBuilder
    var body: some View {
        #if os(tvOS)
        // MainTabView's Movies and TV Shows tabs are the only `library-` tab IDs.
        if episodeRouteTabID?.hasPrefix("library-") == true {
            posterContent.withViewContext(.isMoviesTVLibrary)
        } else {
            posterContent
        }
        #else
        posterContent
        #endif
    }

    private func poster(for item: BaseItemDto) -> some View {
        PosterButton(
            item: item,
            displayType: resolvedLibraryStyle.posterDisplayType,
            routeEpisodeOrigin: episodeRouteOrigin
        ) { namespace in
            item.routeFromLibrarySelection(
                router: router,
                in: namespace,
                episodeRouteOriginContext: episodeRouteOriginContext
            )
        }
    }
}

struct ItemStatePoster: View {

    @ObservedObject
    var itemState: ItemState

    let item: BaseItemDto
    let displayType: PosterDisplayType
    var size: PosterDisplayType.Size = .small
    var routeFocusCoordinator: FocusCoordinator?
    var routeFocusTargetID: String?
    var routeEpisodeOrigin: EpisodeRouteIntent.Origin?
    let action: (BaseItemDto, Namespace.ID) -> Void

    var body: some View {
        let updatedItem = itemState.applying(to: item)
        PosterButton(
            item: updatedItem,
            displayType: displayType,
            size: size,
            routeFocusCoordinator: routeFocusCoordinator,
            routeFocusTargetID: routeFocusTargetID,
            routeEpisodeOrigin: routeEpisodeOrigin
        ) { namespace in
            action(updatedItem, namespace)
        }
    }
}

private struct BaseItemDtoLibraryListElement: View {

    @Namespace
    private var namespace

    @Router
    private var router

    @Environment(\.episodeRouteOriginContext)
    private var episodeRouteOriginContext

    let item: BaseItemDto
    let libraryStyle: LibraryStyle

    private var resolvedLibraryStyle: LibraryStyle {
        item.resolvedLibraryStyle(libraryStyle)
    }

    var body: some View {
        ListRow(insets: .init(vertical: 8, horizontal: EdgeInsets.edgePadding)) {
            PosterImage(
                item: item,
                type: resolvedLibraryStyle.posterDisplayType,
                size: .extraSmall
            )
            .subtleShadow()
            .frame(width: resolvedLibraryStyle.posterDisplayType == .landscape ? baseItemListLandscapeWidth : baseItemListPortraitWidth)
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let program = item.currentProgram {
                    currentProgramView(program)
                } else {
                    accessoryView
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } action: {
            item.routeFromLibrarySelection(
                router: router,
                in: namespace,
                episodeRouteOriginContext: episodeRouteOriginContext
            )
        }
        .matchedTransitionSource(id: "item", in: namespace)
        #if os(tvOS)
        .focusedValue(\.focusedPoster, AnyPoster(item))
        #endif
    }

    @ViewBuilder
    private func currentProgramView(_ program: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let progress = program.progressPercentage {
                ProgressBar(progress: progress)
                    .frame(height: 4)
                    .foregroundStyle(Color.accentColor)
            }

            if let start = program.startDate, let end = program.endDate {
                DotHStack {
                    Text(start, style: .time)
                    Text(end, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        DotHStack {
            if item.type == .episode, let seasonEpisodeLocator = item.seasonEpisodeLabel {
                Text(seasonEpisodeLocator)
            } else if let premiereYear = item.premiereDateYear {
                Text(premiereYear)
            }

            if let runtime = item.runtime {
                Text(runtime, format: .runtime)
            }

            if let officialRating = item.officialRating {
                Text(officialRating)
            }
        }
    }
}
