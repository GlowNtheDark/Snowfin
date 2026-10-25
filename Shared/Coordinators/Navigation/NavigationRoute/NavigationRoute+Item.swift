//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

#if os(tvOS)
import FactoryKit
import Get
#endif

struct EpisodeRouteIntent: Hashable {

    struct Origin: Hashable {
        enum Source: Hashable {
            case home(groupID: String)
            case search(query: String, groupID: String)
            case library(tabID: String, libraryID: String, originIndex: Int?)
        }

        let source: Source
        let itemID: String

        var searchFocusTargetID: String? {
            guard case let .search(_, groupID) = source else { return nil }
            return "search-result:\(groupID.utf8.count):\(groupID):\(itemID)"
        }
    }

    enum FocusTarget: Hashable {
        case episodeArtwork(itemID: String)

        var itemID: String {
            switch self {
            case let .episodeArtwork(itemID):
                itemID
            }
        }

        var coordinatorID: String {
            switch self {
            case let .episodeArtwork(itemID):
                "episode-artwork:\(itemID)"
            }
        }
    }

    let episodeID: String
    let seriesID: String
    let seasonID: String?
    let focusTarget: FocusTarget
    let origin: Origin?

    init?(item: BaseItemDto, origin: Origin? = nil) {
        guard item.type == .episode,
              let episodeID = item.id, !episodeID.isEmpty,
              let seriesID = item.seriesID, !seriesID.isEmpty
        else { return nil }

        self.init(
            episodeID: episodeID,
            seriesID: seriesID,
            seasonID: item.seasonID,
            origin: origin
        )
    }

    init?(episodeID: String, seriesID: String, seasonID: String?, origin: Origin? = nil) {
        guard !episodeID.isEmpty, !seriesID.isEmpty else { return nil }

        self.episodeID = episodeID
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.focusTarget = .episodeArtwork(itemID: episodeID)
        self.origin = origin
    }
}

struct EpisodeRouteOriginContext {

    enum Source {
        case search(query: String)
        case library(tabID: String, libraryID: String)
    }

    let source: Source
    let focusCoordinator: FocusCoordinator?
    let libraryIndexForItemID: ((String) -> Int?)?

    func origin(groupID: String, itemID: String) -> EpisodeRouteIntent.Origin {
        let source: EpisodeRouteIntent.Origin.Source = switch self.source {
        case let .search(query):
            .search(query: query, groupID: groupID)
        case let .library(tabID, libraryID):
            .library(
                tabID: tabID,
                libraryID: libraryID,
                originIndex: libraryIndexForItemID?(itemID)
            )
        }

        return EpisodeRouteIntent.Origin(source: source, itemID: itemID)
    }
}

extension EnvironmentValues {
    @Entry
    var episodeRouteOriginContext: EpisodeRouteOriginContext? = nil

    @Entry
    var episodeRouteTabID: String? = nil

    @Entry
    var episodeRouteOrigin: EpisodeRouteIntent.Origin? = nil
}

extension NavigationRoute {

    // MARK: - Item Editing

    #if os(iOS)
    static func addItemElement<Editor: ItemComponentEditor>(
        viewModel: ItemComponentEditorViewModel<Editor>
    ) -> NavigationRoute {
        NavigationRoute(
            id: "addItemElement-\(Editor.self)",
            style: .sheet
        ) {
            AddItemElementView(viewModel: viewModel)
        }
    }
    #endif

    @MainActor
    static func castAndCrew(people: [BaseItemPerson], itemID: String?) -> NavigationRoute {
        let id = itemID == nil ? "castAndCrew" : "castAndCrew-\(itemID!)"
        let library = StaticLibrary(
            title: L10n.castAndCrew.localizedCapitalized,
            id: id,
            elements: people
        )

        return NavigationRoute(id: "castAndCrew") {
            PagingLibraryView(library: library)
        }
    }

    #if os(iOS)
    @MainActor
    static func editGenres(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "editGenres") {
            EditItemElementView(
                viewModel: ItemComponentEditorViewModel(
                    editor: GenreComponentEditor(),
                    item: item
                )
            )
        }
    }

    @MainActor
    static func editMetadata(viewModel: ItemEditorViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "editMetadata",
            style: .sheet
        ) {
            EditMetadataView(viewModel: viewModel)
        }
    }

    @MainActor
    static func editPeople(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "editPeople") {
            EditItemElementView(
                viewModel: ItemComponentEditorViewModel(
                    editor: PeopleComponentEditor(),
                    item: item
                )
            )
        }
    }

    @MainActor
    static func editStudios(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "editStudios") {
            EditItemElementView(
                viewModel: ItemComponentEditorViewModel(
                    editor: StudioComponentEditor(),
                    item: item
                )
            )
        }
    }

    static func editSubtitles(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(
            id: "editSubtitles",
            style: .sheet
        ) {
            ItemSubtitlesView(item: item)
        }
    }

    @MainActor
    static func editTags(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "editTags") {
            EditItemElementView(
                viewModel: ItemComponentEditorViewModel(
                    editor: TagComponentEditor(),
                    item: item
                )
            )
        }
    }

    static func identifyItem(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "identifyItem") {
            IdentifyItemView(item: item)
        }
    }

    static func identifyItemResults(
        viewModel: IdentifyItemViewModel,
        result: RemoteSearchResult
    ) -> NavigationRoute {
        NavigationRoute(
            id: "identifyItemResults",
            style: .sheet
        ) {
            IdentifyItemResultView(
                viewModel: viewModel,
                result: result
            )
        }
    }

    static func uploadSubtitle(viewModel: ItemSubtitlesViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "uploadSubtitle",
            style: .sheet
        ) {
            ItemSubtitleUploadView(viewModel: viewModel)
        }
    }

    #endif

    static func searchSubtitle(viewModel: ItemSubtitlesViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "searchSubtitle",
            style: .sheet
        ) {
            ItemSubtitleSearchView(viewModel: viewModel)
        }
    }

    @MainActor
    static func item(item: BaseItemDto) -> NavigationRoute {
        let provider = ItemContentGroupProvider(item: item)

        return NavigationRoute(
            id: "item-\(item.id ?? "Unknown")",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ItemView(provider: provider)
        }
    }

    @MainActor
    static func episode(
        item: BaseItemDto,
        origin: EpisodeRouteIntent.Origin? = nil
    ) -> NavigationRoute {
        #if os(tvOS)
        guard let intent = EpisodeRouteIntent(item: item, origin: origin) else {
            return .item(item: item)
        }

        return .episode(intent: intent)
        #else
        .item(item: item)
        #endif
    }

    #if os(tvOS)
    @MainActor
    static func episode(intent: EpisodeRouteIntent) -> NavigationRoute {
        let provider = ItemContentGroupProvider(
            id: intent.seriesID,
            episodeRouteIntent: intent
        )

        return NavigationRoute(
            id: "item-\(intent.seriesID)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) },
            episodeRouteOrigin: intent.origin
        ) {
            ItemView(provider: provider)
        }
    }

    @MainActor
    static func resolvedEpisode(
        item: BaseItemDto,
        origin: EpisodeRouteIntent.Origin? = nil
    ) -> NavigationRoute {
        let id = item.seriesID ?? item.id ?? "Unknown"

        return NavigationRoute(
            id: "item-\(id)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) },
            episodeRouteOrigin: origin
        ) {
            if let episodeID = item.id, !episodeID.isEmpty {
                EpisodeIDRouteResolutionView(
                    itemID: episodeID,
                    origin: origin,
                    fallbackToEpisodeDetails: false
                )
            } else {
                ErrorView(error: ErrorMessage(L10n.unknownError))
            }
        }
    }
    #endif

    @MainActor
    static func item(
        id: String,
        episodeRouteOrigin: EpisodeRouteIntent.Origin? = nil
    ) -> NavigationRoute {
        #if os(tvOS)
        return NavigationRoute(
            id: "item-\(id)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) },
            episodeRouteOrigin: episodeRouteOrigin
        ) {
            EpisodeIDRouteResolutionView(
                itemID: id,
                origin: episodeRouteOrigin,
                fallbackToEpisodeDetails: true
            )
        }
        #else
        let provider = ItemContentGroupProvider(id: id)

        return NavigationRoute(
            id: "item-\(id)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ItemView(provider: provider)
        }
        #endif
    }

    #if os(iOS)
    static func itemEditor(viewModel: ItemEditorViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "itemEditor",
            style: .sheet
        ) {
            ItemEditorView(viewModel: viewModel)
        }
    }

    static func itemImages(viewModel: ItemImageViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "itemImages",
            style: .sheet
        ) {
            ItemImagesView(viewModel: viewModel)
        }
    }

    static func itemImageDetail(viewModel: ItemImageViewModel, imageInfo: ImageInfo) -> NavigationRoute {
        NavigationRoute(
            id: "itemImageDetail",
            style: .sheet
        ) {
            ItemImageDetailView(
                viewModel: viewModel,
                imageInfo: imageInfo
            )
        }
    }

    static func remoteImageDetail(
        viewModel: ItemImageViewModel,
        remoteImageInfo: RemoteImageInfo
    ) -> NavigationRoute {
        NavigationRoute(
            id: "remoteImageDetail",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            RemoteImageDetailView(
                viewModel: viewModel,
                remoteImageInfo: remoteImageInfo
            )
        }
    }

    static func remoteImageSearch(viewModel: ItemImageViewModel, imageType: ImageType) -> NavigationRoute {
        NavigationRoute(
            id: "remoteImageSearch",
            style: .sheet
        ) {
            RemoteImageSearchView(viewModel: viewModel, imageType: imageType)
        }
    }

    #endif

    static func itemMetadataRefresh(viewModel: ItemEditorViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "itemMetadataRefresh",
            style: .sheet
        ) {
            ItemRefreshView(viewModel: viewModel)
        }
    }

    static func itemOverview(item: BaseItemDto) -> NavigationRoute {
        NavigationRoute(
            id: "itemOverview",
            style: .sheet
        ) {
            ItemOverviewView(item: item)
        }
    }
}

#if os(tvOS)
private struct EpisodeIDRouteResolutionView: View {

    private enum Resolution {
        case loading
        case item(BaseItemDto)
        case episode(series: BaseItemDto, intent: EpisodeRouteIntent)
        case error(any Error)
    }

    @Injected(\.currentUserSession)
    private var currentUserSession: UserSession?

    @State
    private var resolution: Resolution = .loading

    let itemID: String
    let origin: EpisodeRouteIntent.Origin?
    let fallbackToEpisodeDetails: Bool

    var body: some View {
        Group {
            switch resolution {
            case .loading:
                ProgressView()
            case let .item(item):
                ItemView(provider: ItemContentGroupProvider(
                    item: item,
                    episodeRouteOrigin: item.type == .episode ? origin : nil
                ))
            case let .episode(series, intent):
                ItemView(provider: ItemContentGroupProvider(
                    item: series,
                    episodeRouteIntent: intent
                ))
            case let .error(error):
                ErrorView(error: error)
            }
        }
        .task(id: itemID) {
            await resolve()
        }
    }

    @MainActor
    private func resolve() async {
        guard let userSession = currentUserSession else {
            resolution = .error(ErrorMessage(L10n.unknownError))
            return
        }

        do {
            let item = try await BaseItemDto(id: itemID).getFullItem(userSession: userSession)
            guard currentUserSession?.id == userSession.id else {
                resolution = .error(ErrorMessage(L10n.unknownError))
                return
            }
            guard item.id == itemID else {
                resolution = .error(ErrorMessage(L10n.unknownError))
                return
            }

            guard item.type == .episode else {
                if fallbackToEpisodeDetails {
                    resolution = .item(item)
                } else {
                    resolution = .error(ErrorMessage(L10n.unknownError))
                }
                return
            }

            guard let seriesID = item.seriesID, !seriesID.isEmpty,
                  let intent = EpisodeRouteIntent(item: item, origin: origin)
            else {
                showEpisodeDetailsOrError(item)
                return
            }

            do {
                let series = try await BaseItemDto(id: seriesID).getFullItem(userSession: userSession)
                guard currentUserSession?.id == userSession.id else {
                    resolution = .error(ErrorMessage(L10n.unknownError))
                    return
                }
                guard series.id == seriesID,
                      series.type == .series,
                      item.seriesID == series.id
                else {
                    showEpisodeDetailsOrError(item)
                    return
                }

                resolution = .episode(series: series, intent: intent)
            } catch is CancellationError {
                return
            } catch {
                showEpisodeDetailsOrError(item, error: error)
            }
        } catch is CancellationError {
            return
        } catch {
            resolution = .error(error)
        }
    }

    @MainActor
    private func showEpisodeDetailsOrError(_ item: BaseItemDto, error: (any Error)? = nil) {
        if fallbackToEpisodeDetails {
            resolution = .item(item)
        } else {
            resolution = .error(error ?? ErrorMessage(L10n.unknownError))
        }
    }
}
#endif
