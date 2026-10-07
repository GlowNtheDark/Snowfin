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
        @State
        private var episodeCollectionRevision = 0

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

        private func refreshLoadedSeasons(for itemID: String) async {
            guard itemID == parentID else { return }

            let loadedSeasons = viewModel.elements.filter {
                $0.id == selection || $0.state != .initial
            }

            for seasonViewModel in loadedSeasons {
                await seasonViewModel.background.refresh()
            }

            episodeCollectionRevision &+= 1
        }

        @ViewBuilder
        var body: some View {
            Group {
                if let selectedSeasonViewModel {
                    SeasonEpisodesView(
                        seasonViewModel: selectedSeasonViewModel,
                        focusSeasonSelector: isSeriesDetails,
                        episodeCollectionRevision: episodeCollectionRevision,
                        playButtonItem: playButtonItem
                    ) {
                        seasonSelectorView
                    }
                } else {
                    LoadingEpisodesView(
                        focusSeasonSelector: isSeriesDetails,
                        episodeCollectionRevision: episodeCollectionRevision
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
            .onReceive(Notifications[.itemShouldRefreshMetadata].publisher.receive(on: DispatchQueue.main)) { itemID in
                Task { @MainActor in
                    await refreshLoadedSeasons(for: itemID)
                }
            }
            #endif
        }
    }
}
