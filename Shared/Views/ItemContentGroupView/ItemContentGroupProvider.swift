//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Get
import JellyfinAPI
import SwiftUI

final class ItemContentGroupProvider: ViewModel, ContentGroupProvider {

    @Published
    private var itemSnapshot: BaseItemDto

    private var itemState: ItemState?
    private var playbackItemState: ItemState?
    private var itemStateSessionID: UUID?
    private var observedItemStateIDs = Set<String>()
    private var itemStateCancellables = Set<AnyCancellable>()
    private var itemSnapshotRequestGeneration = 0

    @Published
    private(set) var localTrailers: [BaseItemDto] = []
    @Published
    private(set) var mediaPlayerItemProvider: MediaPlayerItemProvider?
    @Published
    private(set) var randomBackdropItem: BaseItemDto?
    @Published
    private(set) var isMarkingSeriesUnwatched = false

    let id: String

    var item: BaseItemDto {
        #if os(tvOS)
        guard let itemState,
              itemStateSessionID == userSession?.id
        else { return itemSnapshot }

        return itemState.applying(to: itemSnapshot)
        #else
        itemSnapshot
        #endif
    }

    var currentMediaPlayerItemProvider: MediaPlayerItemProvider? {
        #if os(tvOS)
        guard let mediaPlayerItemProvider,
              let playbackItemState,
              playbackItemStateSessionMatchesCurrentUser,
              playbackItemState.id == mediaPlayerItemProvider.item.id,
              let userSession
        else { return mediaPlayerItemProvider }

        let updatedItem = playbackItemState.applying(to: mediaPlayerItemProvider.item)
        return updatedItem.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaPlayerItemProvider.mediaSource
        ) ?? mediaPlayerItemProvider
        #else
        mediaPlayerItemProvider
        #endif
    }

    private var playbackItemStateSessionMatchesCurrentUser: Bool {
        itemStateSessionID == userSession?.id
    }

    var displayTitle: String {
        item.displayTitle
    }

    init(item: BaseItemDto) {
        self.id = item.id ?? "Unknown"
        self.itemSnapshot = item
        super.init()
    }

    init(id: String) {
        self.id = id
        self.itemSnapshot = .init(id: id)
        super.init()
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        let userSession = try requireUserSession()
        let seedItem = itemSnapshot
        let itemState = bindItemState(for: seedItem, userSession: userSession)
        let itemStateRevision = itemState?.revision
        let requestGeneration = beginItemSnapshotRequest()
        let fullItem = try await seedItem.getFullItem(userSession: userSession, sendNotification: true)
        try requireCurrentSession(userSession)
        guard requestGeneration == itemSnapshotRequestGeneration else {
            throw CancellationError()
        }
        mergeSnapshotUserData(
            from: fullItem,
            into: itemState,
            revisionAtStart: itemStateRevision,
            requestGeneration: requestGeneration
        )
        setItemSnapshot(fullItem)

        let newMediaPlayerItemProvider = try await resolveMediaPlayerItemProvider(
            for: item,
            userSession: userSession
        )
        let newLocalTrailers = try? await localTrailers(for: fullItem)
        let newRandomBackdropItem = try? await randomBackdropItem(for: fullItem)

        try requireCurrentSession(userSession)
        guard requestGeneration == itemSnapshotRequestGeneration else {
            throw CancellationError()
        }
        localTrailers = newLocalTrailers ?? []
        mediaPlayerItemProvider = newMediaPlayerItemProvider
        bindPlaybackItemState(to: newMediaPlayerItemProvider?.item, userSession: userSession)
        randomBackdropItem = newRandomBackdropItem

        return try await _makeGroups(
            item: item,
            itemID: id
        )
    }

    func refreshItem() async throws {
        let userSession = try requireUserSession()
        let itemState = bindItemState(for: itemSnapshot, userSession: userSession)
        let itemStateRevision = itemState?.revision
        let requestGeneration = beginItemSnapshotRequest()
        let refreshedItem = try await itemSnapshot.getFullItem(userSession: userSession)
        try requireCurrentSession(userSession)
        guard requestGeneration == itemSnapshotRequestGeneration else { return }
        mergeSnapshotUserData(
            from: refreshedItem,
            into: itemState,
            revisionAtStart: itemStateRevision,
            requestGeneration: requestGeneration
        )
        setItemSnapshot(refreshedItem)

        guard let mediaPlayerItemProvider,
              mediaPlayerItemProvider.item.id == refreshedItem.id
        else { return }

        let updatedItem = itemState?.applying(to: refreshedItem) ?? refreshedItem
        let refreshedPlaybackItemProvider = updatedItem.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaPlayerItemProvider.mediaSource
        )
        self.mediaPlayerItemProvider = refreshedPlaybackItemProvider
        bindPlaybackItemState(to: refreshedPlaybackItemProvider?.item, userSession: userSession)
    }

    private func bindItemState(for item: BaseItemDto, userSession: UserSession) -> ItemState? {
        #if os(tvOS)
        if itemStateSessionID != userSession.id {
            itemStateCancellables.removeAll()
            observedItemStateIDs.removeAll()
            itemState = nil
            playbackItemState = nil
            itemStateSessionID = userSession.id
        }

        guard let state = userSession.itemStateStore.state(for: item) else { return nil }
        itemState = state
        observeItemState(state)
        return state
        #else
        nil
        #endif
    }

    private func bindPlaybackItemState(to item: BaseItemDto?, userSession: UserSession) {
        #if os(tvOS)
        guard let item,
              let state = userSession.itemStateStore.state(for: item)
        else {
            playbackItemState = nil
            return
        }

        playbackItemState = state
        observeItemState(state)
        #else
        playbackItemState = nil
        #endif
    }

    private func observeItemState(_ state: ItemState) {
        guard observedItemStateIDs.insert(state.id).inserted else { return }

        state.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &itemStateCancellables)
    }

    private func setItemSnapshot(_ item: BaseItemDto) {
        #if os(tvOS)
        var metadataItem = item
        metadataItem.userData = nil
        itemSnapshot = metadataItem
        #else
        itemSnapshot = item
        #endif
    }

    private func beginItemSnapshotRequest() -> Int {
        itemSnapshotRequestGeneration += 1
        return itemSnapshotRequestGeneration
    }

    private func mergeSnapshotUserData(
        from item: BaseItemDto,
        into itemState: ItemState?,
        revisionAtStart: UInt64?,
        requestGeneration: Int
    ) {
        guard requestGeneration == itemSnapshotRequestGeneration,
              let itemState,
              itemStateSessionID == userSession?.id,
              revisionAtStart == 0,
              itemState.revision == revisionAtStart
        else { return }

        itemState.mergeSnapshot(item.userData)
    }

    private func requireCurrentSession(_ session: UserSession) throws {
        guard userSession?.id == session.id else {
            throw CancellationError()
        }
    }

    @ContentGroupBuilder
    private func _makeGroups(item: BaseItemDto, itemID: String) async throws -> [any ContentGroup] {

        if let birthday = item.birthday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.born,
                value: birthday
            )
        }

        if let deathday = item.deathday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.died,
                value: deathday
            )
        }

        if let birthplace = item.birthplace {
            LabeledContentGroup(
                L10n.birthplace,
                value: birthplace
            )
        }

        switch item.type {
        case .season, .series:
            SeriesEpisodeContentGroup(
                parent: item,
                playButtonItem: mediaPlayerItemProvider?.item
            )
        default:
            []
        }

        #if os(tvOS)
        if item.type == .movie {
            let actors = item.people?.filter { person in
                person.type == .actor || person.type == .guestStar
            } ?? []

            if actors.isNotEmpty {
                PosterGroup(
                    id: "actors",
                    library: StaticLibrary(
                        title: L10n.castAndCrew.localizedCapitalized,
                        id: "actors",
                        elements: actors
                    ),
                    posterDisplayType: .portrait,
                    posterSize: .small
                )
            }
        }
        #endif

        #if os(tvOS)
        let shouldShowGenreAndStudioGroups = item.type != .series
        #else
        let shouldShowGenreAndStudioGroups = true
        #endif

        if shouldShowGenreAndStudioGroups,
           let genres = item.itemGenres,
           genres.isNotEmpty
        {
            PillGroup(
                displayTitle: L10n.genres,
                id: "genres",
                elements: genres
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(name: element.displayTitle),
                            environment: .init(filters: .init(genres: [element]))
                        )
                    )
                )
            }
        }

        if shouldShowGenreAndStudioGroups,
           let studios = item.studios,
           studios.isNotEmpty
        {
            PillGroup(
                displayTitle: L10n.studios,
                id: "studios",
                elements: studios
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(id: element.id, name: element.displayTitle, type: .studio)
                        )
                    )
                )
            }
        }

        switch item.type {
        case .movie:
            if item.partCount ?? 0 > 1 {
                PosterGroup(
                    id: "additional-parts",
                    library: AdditionalPartsLibrary(itemID: itemID),
                    posterDisplayType: .landscape,
                    posterSize: .small
                )
            }
        case .boxSet, .person, .musicArtist:
            try await ItemTypeContentGroupProvider(
                itemTypes: BaseItemKind.supportedCases
                    .appending(.episode)
                    .appending(.person),
                parent: item
            )
            .makeGroups(environment: .default)
        case .series:
            try await ItemTypeContentGroupProvider(
                itemTypes: [.season],
                parent: item
            )
            .makeGroups(environment: .default)
        case .channel, .liveTvChannel, .tvChannel:
            PosterGroup(
                id: "channel-programs",
                library: ChannelScheduleLibrary(channel: item),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        default: []
        }

        if item.type == .episode {
            PosterGroup(
                library: StaticLibrary(
                    title: L10n.season,
                    id: "seasons",
                    elements: [BaseItemDto(
                        id: item.seasonID,
                        name: item.seasonName,
                        seriesID: item.seriesID,
                        seriesName: item.seriesName,
                        type: .season
                    )]
                ),
                posterSize: .small,
                environment: .init(isHeaderButtonEnabled: false)
            )
        }

        if let castAndCrew = item.people,
           castAndCrew.isNotEmpty,
           !UIDevice.isTV || item.type != .movie
        {
            PosterGroup(
                id: "cast-and-crew",
                library: StaticLibrary(
                    title: L10n.castAndCrew.localizedCapitalized,
                    id: "cast-and-crew",
                    elements: castAndCrew
                ),
                posterDisplayType: .portrait,
                posterSize: .small
            )
        }

        PosterGroup(
            id: "special-features",
            library: SpecialFeaturesLibrary(itemID: itemID),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        #if os(tvOS)
        if Defaults[.Customization.shouldShowRecommendations], item.type != .movie {
            PosterGroup(
                id: "similar-items",
                library: SimilarItemsLibrary(itemID: itemID, itemType: item.type),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        if item.type != .series {
            AboutItemGroup(
                displayTitle: L10n.about,
                id: "about",
                item: item
            )
        }
        #else
        if Defaults[.Customization.shouldShowRecommendations] {
            PosterGroup(
                id: "similar-items",
                library: SimilarItemsLibrary(itemID: itemID, itemType: item.type),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        AboutItemGroup(
            displayTitle: L10n.about,
            id: "about",
            item: item
        )
        #endif
    }

    func toggleIsFavorite() async {
        let beforeIsFavorite = item.userData?.isFavorite == true
        #if !os(tvOS)
        itemSnapshot.userData?.isFavorite = !beforeIsFavorite
        #endif

        do {
            try await setIsFavorite(!beforeIsFavorite)
        } catch {
            #if !os(tvOS)
            itemSnapshot.userData?.isFavorite = beforeIsFavorite
            #endif
            logger.error("Unable to update favorite state: \(error.localizedDescription)")
        }
    }

    func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed == true
        #if !os(tvOS)
        itemSnapshot.userData?.isPlayed = !beforeIsPlayed
        #endif

        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            #if !os(tvOS)
            itemSnapshot.userData?.isPlayed = beforeIsPlayed
            #endif
            logger.error("Unable to update played state: \(error.localizedDescription)")
        }
    }

    func markSeriesUnwatched() async throws {
        guard item.type == .series else { return }
        guard !isMarkingSeriesUnwatched else { return }
        guard let itemID = item.id else {
            throw ErrorMessage(L10n.unknownError)
        }

        let userSession = try requireUserSession()
        let itemState = bindItemState(for: itemSnapshot, userSession: userSession)
        let requestGeneration = beginItemSnapshotRequest()
        let revision = DispatchTime.now().uptimeNanoseconds

        isMarkingSeriesUnwatched = true
        defer { isMarkingSeriesUnwatched = false }

        let updatedUserData: UserItemDataDto
        do {
            let request = try Paths.markUnplayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
            let response = try await userSession.client.send(request)
            updatedUserData = response.value
        } catch {
            logger.error("Unable to mark series unwatched: \(error.localizedDescription)")

            let refreshRevision = DispatchTime.now().uptimeNanoseconds
            let revisionBeforeRefresh = itemState?.revision
            var refreshedUserData: UserItemDataDto?
            do {
                let refreshedItem = try await itemSnapshot.getFullItem(userSession: userSession)
                try requireCurrentSession(userSession)
                if requestGeneration == itemSnapshotRequestGeneration {
                    setItemSnapshot(refreshedItem)
                    if itemState?.revision == revisionBeforeRefresh {
                        refreshedUserData = refreshedItem.userData
                    }
                }
            } catch {
                logger.error("Unable to refresh series after failed unwatch request: \(error.localizedDescription)")
            }

            if let userData = refreshedUserData {
                Notifications[.itemUserDataDidChange].post(ItemUpdate(
                    userSessionID: userSession.id,
                    itemID: itemID,
                    revision: refreshRevision,
                    change: .userData(userData)
                ))
            } else if item.userData == nil {
                Notifications[.didRequestGlobalRefresh].post()
            } else {
                // A newer item update arrived while the authoritative recovery fetch was in flight.
                // Keep that shared state; loaded episode rows reconcile from their own server query.
            }
            #if os(tvOS)
            Notifications[.seriesDescendantUserDataNeedsReconciliation].post(
                SeriesDescendantUserDataReconciliation(
                    userSessionID: userSession.id,
                    seriesID: itemID
                )
            )
            #endif

            throw ErrorMessage(
                "Could not mark the series as unwatched. Jellyfin may have updated only part of the series. Refresh and check the current state. \(error.localizedDescription)"
            )
        }

        Notifications[.itemUserDataDidChange].post(ItemUpdate(
            userSessionID: userSession.id,
            itemID: itemID,
            revision: revision,
            change: .userData(updatedUserData)
        ))
        #if !os(tvOS)
        itemSnapshot.userData = updatedUserData
        #endif
        #if os(tvOS)
        Notifications[.seriesDescendantUserDataNeedsReconciliation].post(
            SeriesDescendantUserDataReconciliation(
                userSessionID: userSession.id,
                seriesID: itemID
            )
        )
        #endif

        do {
            let refreshedMediaPlayerItemProvider = try await resolveMediaPlayerItemProvider(
                for: item,
                userSession: userSession
            )
            try requireCurrentSession(userSession)
            mediaPlayerItemProvider = refreshedMediaPlayerItemProvider
            bindPlaybackItemState(to: refreshedMediaPlayerItemProvider?.item, userSession: userSession)
        } catch {
            logger.error("Unable to refresh series playback target after unwatch: \(error.localizedDescription)")
            throw ErrorMessage(
                "The series was marked as unwatched, but its playback selection could not be refreshed. Reopen Show Details before playing. \(error.localizedDescription)"
            )
        }
    }

    func selectMediaSource(_ mediaSource: MediaSourceInfo?) {
        guard let mediaPlayerItemProvider = currentMediaPlayerItemProvider,
              let userSession
        else { return }

        self.mediaPlayerItemProvider = mediaPlayerItemProvider.item.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaSource
        )
    }

    private func resolveMediaPlayerItemProvider(
        for item: BaseItemDto,
        userSession: UserSession
    ) async throws -> MediaPlayerItemProvider? {
        let playbackItem: BaseItemDto? = switch item.type {
        case .series:
            if let nextUp = try await nextUpItem(for: item) {
                nextUp
            } else if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }
        case .season:
            if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }
        default:
            item.isPlayable ? item : nil
        }

        return playbackItem?.getPlaybackItemProvider(userSession: userSession)
    }

    private func nextUpItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetNextUpParameters()
        parameters.seriesID = item.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first, !item.isMissing else {
            return nil
        }

        return item
    }

    private func resumeItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.limit = 1
        parameters.parentID = item.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func firstAvailableItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.episode]
        parameters.isMissing = false
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortOrder = [.ascending]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func localTrailers(for item: BaseItemDto) async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        let request = try Paths.getLocalTrailers(itemID: itemID, userID: authenticatedUser.id)
        let response = try await send(request)

        return response.value
    }

    private func randomBackdropItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        guard item.type == .person || item.type == .musicArtist || item.type == .boxSet else {
            return nil
        }

        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.sortBy = [.random]
        parameters.userID = try authenticatedUser.id

        switch item.libraryType {
        case .boxSet, .collectionFolder, .userView:
            parameters.parentID = item.id
        case .person:
            parameters.personIDs = item.id.map { [$0] }
        default:
            parameters.parentID = item.id
        }

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id else { return }
        let userSession = try requireUserSession()
        let revision = DispatchTime.now().uptimeNanoseconds

        let request: Request<UserItemDataDto> = if isPlayed {
            try Paths.markPlayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        } else {
            try Paths.markUnplayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        }

        let response = try await userSession.client.send(request)
        Notifications[.itemUserDataDidChange].post(ItemUpdate(
            userSessionID: userSession.id,
            itemID: itemID,
            revision: revision,
            change: .userData(response.value)
        ))
        #if os(tvOS)
        if item.type == .series {
            Notifications[.seriesDescendantUserDataNeedsReconciliation].post(
                SeriesDescendantUserDataReconciliation(
                    userSessionID: userSession.id,
                    seriesID: itemID
                )
            )
        }
        #endif
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {
        guard let itemID = item.id else { return }
        let userSession = try requireUserSession()
        let revision = DispatchTime.now().uptimeNanoseconds

        let request: Request<UserItemDataDto> = if isFavorite {
            try Paths.markFavoriteItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        } else {
            try Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        }

        let response = try await userSession.client.send(request)
        Notifications[.itemUserDataDidChange].post(ItemUpdate(
            userSessionID: userSession.id,
            itemID: itemID,
            revision: revision,
            change: .userData(response.value)
        ))
    }
}
