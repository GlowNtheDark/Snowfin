//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import JellyfinAPI
import SwiftUI

extension VideoPlayer.PlaybackControls {

    enum EpisodesFocusTarget: Hashable {
        case season(String)
        case episode(String)
    }

    struct EpisodesSurface: View {

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ObservedObject
        private var seasonsViewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        @Default(.accentColor)
        private var accentColor

        @FocusState
        private var focusedTarget: EpisodesFocusTarget?

        @State
        private var selectedSeasonID: String?

        @State
        private var pendingEpisodeFocusSeasonID: String?

        init(queue: EpisodeMediaPlayerQueue) {
            self._seasonsViewModel = ObservedObject(wrappedValue: queue.seasonsViewModel)
        }

        private var selectedSeason: PagingLibraryViewModel<EpisodeLibrary>? {
            guard let selectedSeasonID else { return nil }
            return seasonsViewModel.elements[id: selectedSeasonID]
        }

        private var seriesTitle: String {
            manager.item.seriesName ?? manager.item.parentTitle ?? manager.item.displayTitle
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline, spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.episodes)
                                    .font(.title2.weight(.semibold))

                                Text(seriesTitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if let seasonEpisodeLabel = manager.item.seasonEpisodeLabel {
                                Text(seasonEpisodeLabel)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        seasonSelector

                        episodesContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 72)
                    .padding(.top, 36)
                    .padding(.bottom, 44)
                    .frame(
                        width: geometry.size.width,
                        height: min(geometry.size.height * 0.72, 760),
                        alignment: .topLeading
                    )
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle()
                                    .fill(Color.snowfinDeepNavy.opacity(0.88))
                            }
                    }
                    .overlay {
                        Rectangle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 30, x: 0, y: 16)
                }
            }
            .focusSection()
            .defaultFocus(
                $focusedTarget,
                .episode(manager.item.id ?? manager.item.displayTitle),
                priority: .userInitiated
            )
            .onAppear(perform: restoreCurrentSeason)
            .onReceive(seasonsViewModel.$elements) { _ in
                if selectedSeasonID == nil {
                    restoreCurrentSeason()
                }
            }
            .onChange(of: manager.item.seasonID) {
                restoreCurrentSeason()
            }
            .onChange(of: manager.item.parentIndexNumber) {
                restoreCurrentSeason()
            }
            .onMoveCommand(perform: handleMoveCommand)
        }

        @ViewBuilder
        private var seasonSelector: some View {
            if seasonsViewModel.elements.count > 1 {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(seasonsViewModel.elements) { season in
                                let isSelected = selectedSeasonID == season.id

                                Button {
                                    select(season: season)
                                } label: {
                                    Text(season.library.parent.displayTitle)
                                        .font(.callout.weight(.semibold))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(EpisodesButtonStyle(isSelected: isSelected))
                                .focused($focusedTarget, equals: .season(season.id))
                                .id(season.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .focusSection()
                    .onChange(of: focusedTarget) { _, target in
                        guard case let .season(seasonID) = target else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo(seasonID, anchor: .center)
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private var episodesContent: some View {
            if seasonsViewModel.elements.isEmpty {
                ProgressView()
                    .tint(accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selectedSeason {
                EpisodesShelf(
                    season: selectedSeason,
                    currentEpisodeID: manager.item.id,
                    focusedTarget: $focusedTarget,
                    pendingEpisodeFocusSeasonID: $pendingEpisodeFocusSeasonID,
                    onSelect: select(episode:)
                )
            }
        }

        private func handleMoveCommand(_ direction: MoveCommandDirection) {
            switch direction {
            case .up:
                guard seasonsViewModel.elements.count > 1,
                      case .episode = focusedTarget,
                      let selectedSeason
                else { return }

                focusedTarget = .season(selectedSeason.id)

            case .down:
                guard case .season = focusedTarget,
                      let season = selectedSeason
                else { return }

                focusEpisode(in: season)

            case .left, .right:
                switch focusedTarget {
                case .season:
                    moveSeason(direction: direction)
                case .episode:
                    moveEpisode(direction: direction)
                case .none:
                    break
                }

            default:
                break
            }
        }

        private func moveSeason(direction: MoveCommandDirection) {
            guard case let .season(focusedSeasonID) = focusedTarget,
                  let currentIndex = seasonsViewModel.elements.firstIndex(where: { $0.id == focusedSeasonID })
            else { return }

            let offset: Int
            switch direction {
            case .left:
                offset = -1
            case .right:
                offset = 1
            default:
                return
            }
            let nextIndex = currentIndex + offset
            guard seasonsViewModel.elements.indices.contains(nextIndex) else { return }

            let season = seasonsViewModel.elements[nextIndex]
            select(season: season)
            focusedTarget = .season(season.id)
        }

        private func moveEpisode(direction: MoveCommandDirection) {
            guard case let .episode(focusedEpisodeID) = focusedTarget,
                  let season = selectedSeason
            else { return }

            let episodes = season.elements
            guard let currentIndex = episodes.firstIndex(where: { episodeID($0) == focusedEpisodeID })
            else { return }

            let offset: Int
            switch direction {
            case .left:
                offset = -1
            case .right:
                offset = 1
            default:
                return
            }
            let nextIndex = currentIndex + offset
            guard episodes.indices.contains(nextIndex) else { return }

            focusedTarget = .episode(episodeID(episodes[nextIndex]))
        }

        private func focusEpisode(in season: PagingLibraryViewModel<EpisodeLibrary>) {
            // The shelf owns the episode focus candidates. Leave this request pending
            // until its content publisher can target the registered card; setting the
            // parent FocusState here can be ignored while the shelf is being inserted.
            pendingEpisodeFocusSeasonID = season.id
        }

        private func episodeID(_ episode: BaseItemDto) -> String {
            episode.id ?? episode.displayTitle
        }

        private func restoreCurrentSeason() {
            guard !seasonsViewModel.elements.isEmpty else { return }

            let season = seasonsViewModel.elements.first {
                $0.library.parent.id == manager.item.seasonID
            } ?? seasonsViewModel.elements.first {
                $0.library.parent.indexNumber == manager.item.parentIndexNumber
            } ?? seasonsViewModel.elements.first

            if let season {
                select(season: season)
                focusEpisode(in: season)
            }
        }

        private func select(season: PagingLibraryViewModel<EpisodeLibrary>) {
            selectedSeasonID = season.id

            switch season.state {
            case .initial:
                season.refresh()
            case .error where season.elements.isEmpty:
                season.refresh()
            default:
                break
            }
        }

        private func select(episode: BaseItemDto) {
            EpisodeMediaPlayerQueue.select(episode: episode, using: manager)
            containerState.isPresentingPlaybackEpisodes = false
        }
    }

    private struct EpisodesShelf: View {

        private enum CardMetrics {
            static let width: CGFloat = 340
            static let height: CGFloat = 316
            static let artworkWidth: CGFloat = 330
            static let artworkHeight: CGFloat = 186
            static let metadataSpacing: CGFloat = 10
            static let seasonLabelHeight: CGFloat = 18
            static let titleHeight: CGFloat = 64
            static let runtimeHeight: CGFloat = 18
        }

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Default(.accentColor)
        private var accentColor

        @ObservedObject
        var season: PagingLibraryViewModel<EpisodeLibrary>

        let currentEpisodeID: String?
        let focusedTarget: FocusState<EpisodesFocusTarget?>.Binding
        @Binding
        var pendingEpisodeFocusSeasonID: String?
        let onSelect: (BaseItemDto) -> Void

        var body: some View {
            switch season.state {
            case .initial, .refreshing:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .error:
                Button(L10n.retry) {
                    season.refresh()
                }
                .buttonStyle(EpisodesButtonStyle(isSelected: false))

            case .content:
                if season.elements.isEmpty {
                    Text(L10n.noItems)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 22) {
                                ForEach(season.elements, id: \.id) { episode in
                                    episodeButton(episode)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                        }
                        .scrollIndicators(.hidden)
                        .focusSection()
                        .onReceive(season.$elements) { elements in
                            let initialEpisode = elements.first(where: { $0.id == currentEpisodeID }) ?? elements.first
                            guard let initialEpisode else { return }

                            let itemID = initialEpisode.id ?? initialEpisode.displayTitle

                            if pendingEpisodeFocusSeasonID == season.id || focusedTarget.wrappedValue == nil {
                                focus(initialEpisode, using: scrollProxy)
                            } else {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                        .onChange(of: pendingEpisodeFocusSeasonID) { _, seasonID in
                            guard seasonID == season.id,
                                  let episode = season.elements.first(where: { $0.id == currentEpisodeID }) ?? season.elements.first
                            else { return }

                            focus(episode, using: scrollProxy)
                        }
                        .onChange(of: focusedTarget.wrappedValue) { _, target in
                            guard case let .episode(itemID) = target else { return }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }

        private func focus(_ episode: BaseItemDto, using scrollProxy: ScrollViewProxy) {
            let itemID = episode.id ?? episode.displayTitle
            scrollProxy.scrollTo(itemID, anchor: .center)
            focusedTarget.wrappedValue = .episode(itemID)
            pendingEpisodeFocusSeasonID = nil
        }

        private func episodeButton(_ episode: BaseItemDto) -> some View {
            let itemID = episode.id ?? episode.displayTitle
            let isCurrent = episode.id == currentEpisodeID

            return Button {
                onSelect(episode)
            } label: {
                VStack(alignment: .leading, spacing: CardMetrics.metadataSpacing) {
                    ZStack(alignment: .topLeading) {
                        ImageView(
                            episode.imageSource(
                                .primary,
                                environment: ImageSourceOptions(maxWidth: 480)
                            )
                        )
                        .failure {
                            SystemImageContentView(systemName: episode.systemImage)
                        }
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: CardMetrics.artworkWidth, height: CardMetrics.artworkHeight)
                        .background(Color.snowfinDeepNavy)
                        .clipped()

                        if isCurrent {
                            Label {
                                // swiftlint:disable:next hard_coded_display_string
                                Text("Now Playing")
                            } icon: {
                                Image(systemName: "play.fill")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accentColor.overlayColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Rectangle().fill(accentColor))
                        }
                    }
                    .frame(width: CardMetrics.artworkWidth, height: CardMetrics.artworkHeight)
                    .overlay {
                        Rectangle()
                            .stroke(isCurrent ? accentColor : Color.white.opacity(0.16), lineWidth: isCurrent ? 3 : 1)
                    }

                    Text(episode.seasonEpisodeLabel ?? " ")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: CardMetrics.seasonLabelHeight, alignment: .topLeading)
                        .opacity(episode.seasonEpisodeLabel == nil ? 0 : 1)
                        .accessibilityHidden(episode.seasonEpisodeLabel == nil)

                    Text(episode.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: CardMetrics.titleHeight, alignment: .topLeading)
                        .clipped()

                    Text(episode.runTimeLabel ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: CardMetrics.runtimeHeight, alignment: .topLeading)
                        .opacity(episode.runTimeLabel == nil ? 0 : 1)
                        .accessibilityHidden(episode.runTimeLabel == nil)
                }
                .frame(width: CardMetrics.width, height: CardMetrics.height, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(EpisodesButtonStyle(isSelected: isCurrent))
            .focused(focusedTarget, equals: .episode(itemID))
            // swiftlint:disable:next hard_coded_display_string
            .accessibilityLabel(
                isCurrent ? "\(episode.displayTitle), Now Playing" : episode.displayTitle
            )
            .id(itemID)
        }
    }

    private struct EpisodesButtonStyle: ButtonStyle {

        @Default(.accentColor)
        private var accentColor
        @Environment(\.isFocused)
        private var isFocused

        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.white)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Rectangle()
                                .fill(Color.snowfinDeepNavy.opacity(isSelected ? 0.42 : 0.7))
                        }
                }
                .overlay {
                    Rectangle()
                        .stroke(
                            isFocused ? accentColor : isSelected ? accentColor.opacity(0.92) : Color.white.opacity(0.14),
                            lineWidth: isFocused ? 3 : isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isFocused ? accentColor.opacity(0.24) : .clear,
                    radius: isFocused ? 14 : 0
                )
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.035 : 1)
                .animation(.easeOut(duration: 0.14), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
