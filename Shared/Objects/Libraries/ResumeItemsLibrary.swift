//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct ResumeItemsLibrary: BaseItemKindLibrary {

    let mediaTypes: [MediaType]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.continue, id: "continue-watching")

    var libraryItemTypes: [BaseItemKind] {
        mediaTypes.flatMap(\.supportedLibraryItemTypes)
    }

    init(mediaTypes: [MediaType] = [.video]) {
        self.mediaTypes = mediaTypes
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.enableUserData = true
        parameters.limit = pageState.pageSize
        parameters.mediaTypes = mediaTypes
        parameters.startIndex = pageState.pageOffset
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)
        let resumeItems = response.value.items ?? []

        #if os(tvOS)
        guard mediaTypes.contains(.video) else { return resumeItems }
        return try await continueWatchingItems(
            resumeItems: resumeItems,
            pageState: pageState
        )
        #else
        return resumeItems
        #endif
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<ResumeItemsLibrary>,
        userData: UserItemDataDto
    ) {
        guard let itemID = userData.itemID else { return }

        if userData.isPlayed == true {
            viewModel.elements.removeAll { $0.id == itemID }
            return
        }

        let isAlreadyLoaded = viewModel.elements.contains { $0.id == itemID }
        guard !isAlreadyLoaded else { return }
        guard (userData.playbackPositionTicks ?? 0) > 0 else { return }

        viewModel.scheduleRefreshForItemUserData(minimumInterval: 30)
    }
}

#if os(tvOS)
private extension ResumeItemsLibrary {

    static let completedSeriesRecency: TimeInterval = 14 * 24 * 60 * 60

    func continueWatchingItems(
        resumeItems: [BaseItemDto],
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let cutoff = Date.now.addingTimeInterval(-Self.completedSeriesRecency)

        var nextUpParameters = Paths.GetNextUpParameters()
        nextUpParameters.enableUserData = true
        nextUpParameters.limit = pageState.pageSize
        nextUpParameters.nextUpDateCutoff = cutoff
        nextUpParameters.userID = pageState.userSession.user.id

        var recentEpisodesParameters = Paths.GetItemsParameters()
        recentEpisodesParameters.enableUserData = true
        recentEpisodesParameters.includeItemTypes = [.episode]
        recentEpisodesParameters.isPlayed = true
        recentEpisodesParameters.isRecursive = true
        recentEpisodesParameters.limit = pageState.pageSize * 5
        recentEpisodesParameters.sortBy = [.datePlayed]
        recentEpisodesParameters.sortOrder = [.descending]
        recentEpisodesParameters.userID = pageState.userSession.user.id

        async let nextUpResponse = pageState.userSession.client.send(
            Paths.getNextUp(parameters: nextUpParameters)
        )
        async let recentEpisodesResponse = pageState.userSession.client.send(
            Paths.getItems(parameters: recentEpisodesParameters)
        )
        let nextUpItems = try await nextUpResponse.value.items ?? []
        let recentEpisodes = try await recentEpisodesResponse.value.items ?? []

        let activityBySeries = recentEpisodes.reduce(into: [String: Date]()) { activity, item in
            guard let key = item.continueWatchingSeriesKey,
                  let lastPlayed = item.userData?.lastPlayedDate,
                  lastPlayed >= cutoff
            else { return }

            activity[key] = max(activity[key] ?? .distantPast, lastPlayed)
        }

        let partialEpisodes = deduplicatedEpisodes(
            resumeItems.filter { item in
                item.type == .episode &&
                    item.userData?.isPlayed != true &&
                    (item.userData?.playbackPositionTicks ?? 0) > 0
            }
        )
        let partialSeries = Set(partialEpisodes.compactMap(\.continueWatchingSeriesKey))
        let nextEpisodes = deduplicatedEpisodes(
            nextUpItems.filter { item in
                guard let key = item.continueWatchingSeriesKey else { return false }
                return !partialSeries.contains(key) && activityBySeries[key] != nil
            }
        )
        let seriesEntries = partialEpisodes + nextEpisodes
        let movieEntries = resumeItems.filter { $0.type != .episode }

        return (seriesEntries + movieEntries)
            .sorted { lhs, rhs in
                let lhsActivity = lhs.continueWatchingActivity(using: activityBySeries)
                let rhsActivity = rhs.continueWatchingActivity(using: activityBySeries)
                return lhsActivity > rhsActivity
            }
    }

    func deduplicatedEpisodes(_ episodes: [BaseItemDto]) -> [BaseItemDto] {
        var series = Set<String>()
        return episodes.filter { item in
            guard let key = item.continueWatchingSeriesKey else { return true }
            return series.insert(key).inserted
        }
    }
}

private extension BaseItemDto {

    func continueWatchingActivity(using activityBySeries: [String: Date]) -> Date {
        userData?.lastPlayedDate ?? activityBySeries[continueWatchingSeriesKey ?? ""] ?? .distantPast
    }

    var continueWatchingSeriesKey: String? {
        if let seriesID, seriesID.isNotEmpty {
            return "id:\(seriesID)"
        }
        guard let seriesName = seriesName?.trimmingCharacters(in: .whitespacesAndNewlines),
              seriesName.isNotEmpty
        else { return nil }
        return "name:\(seriesName.lowercased())"
    }
}
#endif

private extension MediaType {

    var supportedLibraryItemTypes: [BaseItemKind] {
        switch self {
        case .audio:
            [.audio, .musicAlbum]
        case .video:
            [.episode, .movie, .video]
        case .book:
            [.book]
        case .photo:
            [.photo]
        case .unknown:
            []
        }
    }
}
