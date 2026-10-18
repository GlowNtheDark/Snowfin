//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: when used for single seasons, have title as just "Episodes" or
//       have functionality in PosterGroup

struct SeriesEpisodeContentGroup: ContentGroup, Identifiable {

    let id: String
    let parentID: String?
    let isSeriesDetails: Bool
    let playButtonItem: BaseItemDto?
    let episodeRouteIntent: EpisodeRouteIntent?
    let viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty || episodeRouteIntent != nil
    }

    init(
        parent: BaseItemDto,
        playButtonItem: BaseItemDto? = nil,
        episodeRouteIntent: EpisodeRouteIntent? = nil
    ) {
        self.id = "\(parent.id ?? "parent")-episode-selector"
        self.parentID = parent.id
        self.isSeriesDetails = parent.type == .series
        self.playButtonItem = playButtonItem
        self.episodeRouteIntent = episodeRouteIntent
        self.viewModel = .init(library: SeasonViewModelLibrary(parent: parent), pageSize: 100)
    }

    func body(with viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>) -> Body {
        Body(
            viewModel: viewModel,
            parentID: parentID,
            isSeriesDetails: isSeriesDetails,
            playButtonItem: playButtonItem,
            episodeRouteIntent: episodeRouteIntent
        )
    }

    struct Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        let parentID: String?
        let isSeriesDetails: Bool
        let playButtonItem: BaseItemDto?
        let episodeRouteIntent: EpisodeRouteIntent?

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?
        @State
        private var didResolveEpisodeRouteSeason = false
        @State
        private var isResolvingEpisodeRouteSeason = false
        @State
        private var didResolveInitialEpisodeRouteFocus = false

        private var selectedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            viewModel.elements.first { $0.id == selection }
        }

        private var seasonSelectorView: some View {
            SeasonSelector(
                seasons: Array(viewModel.elements),
                selection: $selection,
                preferredSelection: episodeRouteIntent == nil
                    ? selection ?? preferredSeasonSelection()
                    : selection,
                isDisabled: isEpisodeArtworkFocusPending
            )
        }

        private var isEpisodeArtworkFocusPending: Bool {
            guard episodeRouteIntent != nil else { return false }
            return focusCoordinator.hasPendingFocusRequest
        }

        private func preferredSeasonSelection() -> PagingLibraryViewModel<EpisodeLibrary>.ID? {
            if let playButtonSeasonID = playButtonItem?.seasonID,
               viewModel.elements.contains(where: { $0.id == playButtonSeasonID })
            {
                return playButtonSeasonID
            }

            return viewModel.elements.first?.id
        }

        private func selectPreferredSeasonIfNeeded() {
            if episodeRouteIntent != nil {
                resolveEpisodeRouteSeasonIfNeeded()
                return
            }

            if selection == nil || !viewModel.elements.contains(where: { $0.id == selection }) {
                selection = preferredSeasonSelection()
            }
        }

        private func resolveEpisodeRouteSeasonIfNeeded() {
            guard let episodeRouteIntent,
                  viewModel.state == .content,
                  !didResolveEpisodeRouteSeason,
                  !isResolvingEpisodeRouteSeason
            else { return }

            if let intendedSeasonID = episodeRouteIntent.seasonID,
               viewModel.elements.contains(where: { $0.id == intendedSeasonID })
            {
                didResolveEpisodeRouteSeason = true
                selection = intendedSeasonID
                return
            }

            guard viewModel.elements.isNotEmpty else {
                didResolveEpisodeRouteSeason = true
                focusCoordinator.focus(ItemView.Component.play)
                return
            }

            let userSessionID = viewModel.userSession?.id
            isResolvingEpisodeRouteSeason = true
            Task { @MainActor in
                let verifiedSeasonID = await verifiedEpisodeSeasonID(for: episodeRouteIntent)
                guard viewModel.userSession?.id == userSessionID else {
                    isResolvingEpisodeRouteSeason = false
                    return
                }

                isResolvingEpisodeRouteSeason = false
                didResolveEpisodeRouteSeason = true
                selection = viewModel.elements.first(where: { $0.id == verifiedSeasonID })?.id
                    ?? viewModel.elements.first?.id

                if selection == nil {
                    focusCoordinator.focus(ItemView.Component.play)
                }
            }
        }

        private func verifiedEpisodeSeasonID(for intent: EpisodeRouteIntent) async -> String? {
            guard let userSession = viewModel.userSession else { return nil }

            do {
                let episode = try await BaseItemDto(id: intent.episodeID).getFullItem(userSession: userSession)
                guard viewModel.userSession?.id == userSession.id,
                      episode.id == intent.episodeID,
                      episode.type == .episode,
                      episode.seriesID == intent.seriesID
                else { return nil }
                return episode.seasonID
            } catch {
                return nil
            }
        }

        private func refreshSelectedSeasonIfNeeded() {
            guard let selectedSeasonViewModel, selectedSeasonViewModel.state == .initial else { return }
            selectedSeasonViewModel.refresh()
        }

        private func reconcileLoadedItemUserData(
            for reconciliation: SeriesDescendantUserDataReconciliation
        ) async {
            guard reconciliation.seriesID == parentID,
                  let userSession = viewModel.userSession,
                  userSession.id == reconciliation.userSessionID
            else { return }

            let loadedEpisodeSeasons = viewModel.elements.filter {
                $0.id == selection || $0.state != .initial
            }
            var seenItemIDs = Set<String>()
            let seasonIDs = viewModel.elements
                .compactMap(\.library.parent.id)
                .filter { seenItemIDs.insert($0).inserted }
            let episodeIDs = loadedEpisodeSeasons
                .flatMap(\.elements)
                .compactMap(\.id)
                .filter { seenItemIDs.insert($0).inserted }
            let itemIDs = seasonIDs + episodeIDs

            guard itemIDs.isNotEmpty else { return }

            for offset in stride(from: 0, to: itemIDs.count, by: 100) {
                let batchIDs = Array(itemIDs[offset ..< min(offset + 100, itemIDs.count)])
                let requestedIDs = Set(batchIDs)
                let revision = DispatchTime.now().uptimeNanoseconds

                var parameters = Paths.GetItemsParameters()
                parameters.enableUserData = true
                parameters.ids = batchIDs
                parameters.userID = userSession.user.id

                do {
                    let response = try await userSession.client.send(
                        Paths.getItems(parameters: parameters)
                    )
                    guard viewModel.userSession?.id == userSession.id else { return }

                    for item in response.value.items ?? [] {
                        guard let itemID = item.id,
                              requestedIDs.contains(itemID),
                              let userData = item.userData
                        else { continue }

                        Notifications[.itemUserDataDidChange].post(ItemUpdate(
                            userSessionID: userSession.id,
                            itemID: itemID,
                            revision: revision,
                            change: .userData(userData)
                        ))
                    }
                } catch {
                    viewModel.logger.error(
                        "Unable to reconcile loaded season and episode user data after a series update: \(error.localizedDescription)"
                    )
                    return
                }
            }
        }

        @ViewBuilder
        var body: some View {
            Group {
                if let selectedSeasonViewModel {
                    SeasonEpisodesView(
                        seasonViewModel: selectedSeasonViewModel,
                        focusSeasonSelector: isSeriesDetails && episodeRouteIntent == nil,
                        playButtonItem: playButtonItem,
                        episodeRouteIntent: episodeRouteIntent,
                        didResolveInitialEpisodeRouteFocus: $didResolveInitialEpisodeRouteFocus
                    ) {
                        seasonSelectorView
                    }
                } else if episodeRouteIntent != nil,
                          viewModel.state == .content,
                          viewModel.elements.isEmpty
                {
                    EmptyView()
                } else {
                    LoadingEpisodesView(
                        focusSeasonSelector: isSeriesDetails && episodeRouteIntent == nil,
                        isEpisodeRoute: episodeRouteIntent != nil
                    ) {
                        seasonSelectorView
                    }
                }
            }
            .onFirstAppear {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: viewModel.elements.count) { _, _ in
                selectPreferredSeasonIfNeeded()
            }
            .onChange(of: viewModel.state == .content) { _, isLoaded in
                guard isLoaded else { return }
                selectPreferredSeasonIfNeeded()
            }
            .onChange(of: selection) { _, _ in
                refreshSelectedSeasonIfNeeded()
            }
            #if os(tvOS)
            .onReceive(
                Notifications[.seriesDescendantUserDataNeedsReconciliation].publisher
                    .receive(on: DispatchQueue.main)
            ) { reconciliation in
                Task { @MainActor in
                    await reconcileLoadedItemUserData(for: reconciliation)
                }
            }
            #endif
        }
    }
}
