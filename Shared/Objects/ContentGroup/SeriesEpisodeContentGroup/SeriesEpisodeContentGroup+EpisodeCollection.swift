//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import SwiftUI

extension SeriesEpisodeContentGroup {

    private enum EpisodeElement: Identifiable {
        case empty
        case episode(BaseItemDto)
        case error(Error)
        case loading(Int)

        static var loadingElements: [Self] {
            (0 ..< 10).map { .loading($0) }
        }

        var id: String {
            switch self {
            case .empty:
                "empty"
            case let .episode(episode):
                episode.id ?? episode.displayTitle
            case .error:
                "error"
            case let .loading(index):
                "loading-\(index)"
            }
        }
    }

    struct LoadingEpisodesView<Header: View>: View {

        let focusSeasonSelector: Bool
        let isEpisodeRoute: Bool
        let header: Header

        init(
            focusSeasonSelector: Bool,
            isEpisodeRoute: Bool = false,
            @ViewBuilder header: () -> Header
        ) {
            self.focusSeasonSelector = focusSeasonSelector
            self.isEpisodeRoute = isEpisodeRoute
            self.header = header()
        }

        var body: some View {
            EpisodeCollectionLayout(
                elements: EpisodeElement.loadingElements,
                preferredElementID: isEpisodeRoute ? nil : EpisodeElement.loadingElements.first?.id,
                focusSeasonSelector: focusSeasonSelector,
                isEpisodeRoute: isEpisodeRoute
            ) {
                header
            } content: { element, _ in
                EpisodeElementCard(element: element, refresh: {})
            }
            .scrollDisabled(true)
        }
    }

    struct SeasonEpisodesView<Header: View>: View {

        @ObservedObject
        var seasonViewModel: PagingLibraryViewModel<EpisodeLibrary>

        let focusSeasonSelector: Bool
        let playButtonItem: BaseItemDto?
        let episodeRouteIntent: EpisodeRouteIntent?

        @Binding
        var didResolveInitialEpisodeRouteFocus: Bool

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        let header: Header

        init(
            seasonViewModel: PagingLibraryViewModel<EpisodeLibrary>,
            focusSeasonSelector: Bool,
            playButtonItem: BaseItemDto?,
            episodeRouteIntent: EpisodeRouteIntent?,
            didResolveInitialEpisodeRouteFocus: Binding<Bool>,
            @ViewBuilder header: () -> Header
        ) {
            self.seasonViewModel = seasonViewModel
            self.focusSeasonSelector = focusSeasonSelector
            self.playButtonItem = playButtonItem
            self.episodeRouteIntent = episodeRouteIntent
            self._didResolveInitialEpisodeRouteFocus = didResolveInitialEpisodeRouteFocus
            self.header = header()
        }

        private var elements: [EpisodeElement] {
            switch seasonViewModel.state {
            case .content:
                if seasonViewModel.elements.isEmpty {
                    [.empty]
                } else {
                    seasonViewModel.elements.map(EpisodeElement.episode)
                }
            case .error:
                [seasonViewModel.error.map(EpisodeElement.error) ?? .error(ErrorMessage(L10n.unknownError))]
            case .initial, .refreshing:
                EpisodeElement.loadingElements
            }
        }

        private var preferredElementID: EpisodeElement.ID? {
            if let episodeRouteIntent {
                guard seasonViewModel.state == .content else { return nil }

                let playableEpisodes = seasonViewModel.elements.filter(\.isPlayable)
                return playableEpisodes.first(where: { $0.id == episodeRouteIntent.episodeID })?.id
                    ?? playableEpisodes.first?.id
            }

            if let playButtonItemID = playButtonItem?.id,
               elements.contains(where: { $0.id == playButtonItemID })
            {
                return playButtonItemID
            }

            return elements.first?.id
        }

        private var preferredElementIndex: Int? {
            guard let preferredElementID else { return nil }
            return elements.firstIndex(where: { $0.id == preferredElementID })
        }

        private var initialArtworkFocusTarget: EpisodeRouteIntent.FocusTarget? {
            guard let episodeRouteIntent,
                  seasonViewModel.state == .content
            else { return nil }

            let targetEpisode = seasonViewModel.elements.first(where: {
                $0.id == episodeRouteIntent.episodeID && $0.isPlayable
            }) ?? seasonViewModel.elements.first(where: \.isPlayable)

            guard let targetEpisode, let id = targetEpisode.id else { return nil }
            return .episodeArtwork(itemID: id)
        }

        private func resolveInitialEpisodeRouteFocusIfNeeded() {
            guard episodeRouteIntent != nil,
                  !didResolveInitialEpisodeRouteFocus,
                  seasonViewModel.state == .content || seasonViewModel.state == .error
            else { return }

            didResolveInitialEpisodeRouteFocus = true

            guard initialArtworkFocusTarget != nil else {
                focusCoordinator.focus(ItemView.Component.play)
                return
            }
        }

        var body: some View {
            EpisodeCollectionLayout(
                elements: elements,
                preferredElementID: preferredElementID,
                episodeRouteTargetIndex: preferredElementIndex,
                episodeRouteArtworkFocusID: initialArtworkFocusTarget?.coordinatorID,
                focusSeasonSelector: focusSeasonSelector,
                isEpisodeRoute: episodeRouteIntent != nil
            ) {
                header
            } content: { element, onArtworkFocusActionAppear in
                EpisodeElementCard(
                    element: element,
                    isEpisodeRoute: episodeRouteIntent != nil,
                    artworkFocusTarget: initialArtworkFocusTarget,
                    onArtworkFocusActionAppear: onArtworkFocusActionAppear
                ) {
                    seasonViewModel.refresh()
                }
            }
            .scrollDisabled(seasonViewModel.state != .content)
            .onAppear {
                resolveInitialEpisodeRouteFocusIfNeeded()
            }
            .onChange(of: seasonViewModel.state == .content || seasonViewModel.state == .error) { _, isLoaded in
                guard isLoaded else { return }
                resolveInitialEpisodeRouteFocusIfNeeded()
            }
        }
    }

    private struct EpisodeCollectionLayout<Header: View, Content: View>: View {

        private enum FocusedSection: Hashable {
            case seasons
            case episodes
        }

        @FocusState
        private var focusedSection: FocusedSection?
        @FocusState
        private var focusedElement: EpisodeElement.ID?
        @StateObject
        private var collectionProxy = CollectionHStackProxy()
        @State
        private var revealedEpisodeRouteTargetID: EpisodeElement.ID?
        @State
        private var episodeRouteTargetElementID: EpisodeElement.ID?
        @State
        private var episodeRouteTargetIndex: Int?
        @State
        private var episodeRouteArtworkFocusID: String?
        @State
        private var registeredEpisodeRouteArtworkActionID: EpisodeElement.ID?
        @State
        private var hasRegisteredEpisodeElements = false
        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        let elements: [EpisodeElement]
        let preferredElementID: EpisodeElement.ID?
        let initialEpisodeRouteTargetIndex: Int?
        let initialEpisodeRouteArtworkFocusID: String?
        let focusSeasonSelector: Bool
        let isEpisodeRoute: Bool
        let header: Header
        let content: (EpisodeElement, @escaping () -> Void) -> Content

        init(
            elements: [EpisodeElement],
            preferredElementID: EpisodeElement.ID?,
            episodeRouteTargetIndex: Int? = nil,
            episodeRouteArtworkFocusID: String? = nil,
            focusSeasonSelector: Bool = false,
            isEpisodeRoute: Bool = false,
            @ViewBuilder header: () -> Header,
            @ViewBuilder content: @escaping (EpisodeElement, @escaping () -> Void) -> Content
        ) {
            self.elements = elements
            self.preferredElementID = preferredElementID
            self.initialEpisodeRouteTargetIndex = episodeRouteTargetIndex
            self.initialEpisodeRouteArtworkFocusID = episodeRouteArtworkFocusID
            self.focusSeasonSelector = focusSeasonSelector
            self.isEpisodeRoute = isEpisodeRoute
            self.header = header()
            self.content = content
            self._episodeRouteTargetElementID = State(initialValue: isEpisodeRoute ? preferredElementID : nil)
            self._episodeRouteTargetIndex = State(initialValue: isEpisodeRoute ? episodeRouteTargetIndex : nil)
            self._episodeRouteArtworkFocusID = State(initialValue: isEpisodeRoute ? episodeRouteArtworkFocusID : nil)
        }

        private static var layout: CollectionHStackLayout {
            #if os(tvOS)
            .grid(
                columns: 3.5,
                rows: 1,
                columnTrailingInset: 0
            )
            #else
            if UIDevice.isPad {
                .minimumWidth(
                    columnWidth: 300,
                    rows: 1
                )
            } else {
                .grid(
                    columns: 1.5,
                    rows: 1,
                    columnTrailingInset: 0
                )
            }
            #endif
        }

        private static var itemSpacing: CGFloat {
            #if os(tvOS)
            40
            #else
            EdgeInsets.edgePadding / 2
            #endif
        }

        private var defaultFocusedSection: FocusedSection {
            #if os(tvOS)
            isEpisodeRoute ? .episodes : (focusSeasonSelector ? .seasons : .episodes)
            #else
            .episodes
            #endif
        }

        private var isEpisodeRouteFocusPending: Bool {
            isEpisodeRoute && focusCoordinator.hasPendingFocusRequest
        }

        private var focusedEpisodeElementID: EpisodeElement.ID? {
            isEpisodeRoute ? episodeRouteTargetElementID : preferredElementID
        }

        private func revealEpisodeRouteTargetIfNeeded() {
            guard isEpisodeRouteFocusPending,
                  focusCoordinator.request == nil,
                  hasRegisteredEpisodeElements,
                  let targetID = episodeRouteTargetElementID,
                  let targetIndex = episodeRouteTargetIndex,
                  episodeRouteArtworkFocusID != nil
            else { return }

            collectionProxy.scrollTo(index: targetIndex, animated: false)
            revealedEpisodeRouteTargetID = targetID
            requestInitialEpisodeArtworkFocusIfReady()
        }

        private func requestInitialEpisodeArtworkFocusIfReady() {
            guard isEpisodeRouteFocusPending,
                  registeredEpisodeRouteArtworkActionID == episodeRouteTargetElementID,
                  revealedEpisodeRouteTargetID == episodeRouteTargetElementID,
                  let artworkFocusID = episodeRouteArtworkFocusID,
                  focusCoordinator.request == nil
            else { return }

            focusCoordinator.focus(artworkFocusID)
        }

        private func episodeCollectionElementDidAppear(_ element: EpisodeElement) {
            guard case .episode = element else { return }
            hasRegisteredEpisodeElements = true
            revealEpisodeRouteTargetIfNeeded()
        }

        private func episodeRouteArtworkActionDidAppear(for element: EpisodeElement) {
            guard isEpisodeRoute else { return }

            registeredEpisodeRouteArtworkActionID = element.id
            revealEpisodeRouteTargetIfNeeded()
        }

        var body: some View {
            ContentGroupSection {
                CollectionHStack(
                    uniqueElements: elements,
                    layout: Self.layout
                ) { element in
                    content(element) {
                        episodeRouteArtworkActionDidAppear(for: element)
                    }
                    .onAppear {
                        episodeCollectionElementDidAppear(element)
                    }
                    .focused($focusedElement, equals: element.id)
                }
                .proxy(collectionProxy)
                .clipsToBounds(false)
                .insets(horizontal: EdgeInsets.edgePadding)
                .itemSpacing(Self.itemSpacing)
                .scrollBehavior(.continuousLeadingEdge)
                .focusSection()
                .focused($focusedSection, equals: .episodes)
                .defaultFocus(
                    $focusedElement,
                    isEpisodeRoute ? focusedEpisodeElementID : preferredElementID,
                    priority: .userInitiated
                )
            } header: {
                header
                    .focusSection()
                    .focused($focusedSection, equals: .seasons)
            }
            .focusSection()
            .defaultFocus(
                $focusedSection,
                defaultFocusedSection,
                priority: .userInitiated
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.seasons)
            .onChange(of: preferredElementID) { _, targetID in
                guard isEpisodeRoute else { return }
                episodeRouteTargetElementID = targetID
                episodeRouteTargetIndex = initialEpisodeRouteTargetIndex
                revealedEpisodeRouteTargetID = nil
                revealEpisodeRouteTargetIfNeeded()
            }
            .onChange(of: initialEpisodeRouteArtworkFocusID) { _, focusID in
                episodeRouteArtworkFocusID = focusID
                revealEpisodeRouteTargetIfNeeded()
            }
        }
    }

    private struct EpisodeElementCard: View {

        let element: EpisodeElement
        var isEpisodeRoute = false
        var artworkFocusTarget: EpisodeRouteIntent.FocusTarget?
        var onArtworkFocusActionAppear: (() -> Void)?
        let refresh: () -> Void

        @ViewBuilder
        var body: some View {
            switch element {
            case .empty:
                EpisodeStateCard(
                    title: L10n.noResults,
                    subHeader: .emptyDash,
                    content: L10n.noEpisodesAvailable,
                    systemImage: nil,
                    action: {}
                )
                .disabled(true)
            case let .episode(episode):
                EpisodeCard(
                    episode: episode,
                    isEpisodeRoute: isEpisodeRoute,
                    artworkFocusTarget: artworkFocusTarget?.itemID == episode.id
                        ? artworkFocusTarget
                        : nil,
                    onArtworkFocusActionAppear: artworkFocusTarget?.itemID == episode.id
                        ? onArtworkFocusActionAppear
                        : nil
                )
            case let .error(error):
                EpisodeStateCard(
                    title: L10n.error,
                    subHeader: .emptyDash,
                    content: error.localizedDescription,
                    systemImage: "arrow.clockwise",
                    action: refresh
                )
            case .loading:
                EpisodeStateCard(
                    title: String.random(count: 10 ..< 20),
                    subHeader: String.random(count: 7 ..< 12),
                    content: String.random(count: 20 ..< 80),
                    systemImage: nil,
                    action: {}
                )
                .redacted(reason: .placeholder)
                .disabled(true)
            }
        }
    }
}
