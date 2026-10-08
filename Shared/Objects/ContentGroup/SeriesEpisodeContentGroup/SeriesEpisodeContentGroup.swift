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
    let viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    init(
        parent: BaseItemDto,
        playButtonItem: BaseItemDto? = nil
    ) {
        self.id = "\(parent.id ?? "parent")-episode-selector"
        self.parentID = parent.id
        self.isSeriesDetails = parent.type == .series
        self.playButtonItem = playButtonItem
        self.viewModel = .init(library: SeasonViewModelLibrary(parent: parent), pageSize: 100)
    }

    func body(with viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>) -> Body {
        Body(
            viewModel: viewModel,
            parentID: parentID,
            isSeriesDetails: isSeriesDetails,
            playButtonItem: playButtonItem
        )
    }

    struct Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        let parentID: String?
        let isSeriesDetails: Bool
        let playButtonItem: BaseItemDto?

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?

        private var selectedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            viewModel.elements.first { $0.id == selection }
        }

        private var seasonSelectorView: some View {
            SeasonSelector(
                seasons: Array(viewModel.elements),
                selection: $selection,
                preferredSelection: selection ?? preferredSeasonSelection()
            )
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
            if selection == nil || !viewModel.elements.contains(where: { $0.id == selection }) {
                selection = preferredSeasonSelection()
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
                        focusSeasonSelector: isSeriesDetails,
                        playButtonItem: playButtonItem
                    ) {
                        seasonSelectorView
                    }
                } else {
                    LoadingEpisodesView(
                        focusSeasonSelector: isSeriesDetails
                    ) {
                        seasonSelectorView
                    }
                }
            }
            .onFirstAppear {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: viewModel.elements.count) {
                selectPreferredSeasonIfNeeded()
            }
            .onChange(of: selection) {
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
