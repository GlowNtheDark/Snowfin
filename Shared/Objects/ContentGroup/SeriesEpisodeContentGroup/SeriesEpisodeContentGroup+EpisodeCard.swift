//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeriesEpisodeContentGroup {

    struct EpisodeCard: View {

        @Environment(\.itemStateStore)
        private var itemStateStore

        let episode: BaseItemDto
        var isEpisodeRoute = false
        var artworkFocusTarget: EpisodeRouteIntent.FocusTarget?
        var onArtworkFocusActionAppear: (() -> Void)?

        var body: some View {
            if let itemState = itemStateStore?.state(for: episode) {
                EpisodeCardWithItemState(
                    itemState: itemState,
                    episode: episode,
                    isEpisodeRoute: isEpisodeRoute,
                    artworkFocusTarget: artworkFocusTarget,
                    onArtworkFocusActionAppear: onArtworkFocusActionAppear
                )
            } else {
                EpisodeCardContent(
                    episode: episode,
                    isEpisodeRoute: isEpisodeRoute,
                    artworkFocusTarget: artworkFocusTarget,
                    onArtworkFocusActionAppear: onArtworkFocusActionAppear
                )
            }
        }
    }

    private struct EpisodeCardWithItemState: View {

        @ObservedObject
        var itemState: ItemState

        let episode: BaseItemDto
        let isEpisodeRoute: Bool
        let artworkFocusTarget: EpisodeRouteIntent.FocusTarget?
        let onArtworkFocusActionAppear: (() -> Void)?

        var body: some View {
            EpisodeCardContent(
                episode: itemState.applying(to: episode),
                isEpisodeRoute: isEpisodeRoute,
                artworkFocusTarget: artworkFocusTarget,
                onArtworkFocusActionAppear: onArtworkFocusActionAppear
            )
        }
    }

    private struct EpisodeCardContent: View {

        @Environment(\.posterConfiguration)
        private var posterConfiguration

        #if os(tvOS)
        @Environment(\.screenTheme)
        private var screenTheme
        #endif

        @Namespace
        private var namespace

        @Router
        private var router

        let episode: BaseItemDto
        let isEpisodeRoute: Bool
        let artworkFocusTarget: EpisodeRouteIntent.FocusTarget?
        let onArtworkFocusActionAppear: (() -> Void)?

        /// Only Jellyfin's explicit user state selects the completed styling.
        private var isWatched: Bool {
            episode.userData?.isPlayed == true
        }

        @ViewBuilder
        private var overlayView: some View {
            #if os(tvOS)
            if posterConfiguration.indicators.contains(.played), isWatched {
                ProgressIndicator(
                    title: nil,
                    progress: 1,
                    posterDisplayType: .landscape,
                    isCompleted: true,
                    semanticPalette: screenTheme
                )
            } else if posterConfiguration.indicators.contains(.progress), let progressLabel = episode.progressLabel {
                ProgressIndicator(
                    title: progressLabel,
                    progress: episode.progressPercentage ?? 0,
                    posterDisplayType: .landscape,
                    isCompleted: false,
                    semanticPalette: screenTheme
                )
            }
            #else
            if posterConfiguration.indicators.contains(.progress), let progressLabel = episode.progressLabel {
                ProgressIndicator(
                    title: progressLabel,
                    progress: episode.progressPercentage ?? 0,
                    posterDisplayType: .landscape,
                    isCompleted: false
                )
            } else if posterConfiguration.indicators.contains(.played), isWatched {
                PlayedIndicator()
                    .frame(width: UIDevice.isTV ? 45 : 25, height: UIDevice.isTV ? 45 : 25)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            #endif
        }

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        var body: some View {
            EpisodeCardLayout(
                header: episode.displayTitle,
                subHeader: episode.episodeLocator ?? .emptyDash,
                content: episodeContent,
                artworkFocusTarget: artworkFocusTarget,
                onArtworkFocusActionAppear: onArtworkFocusActionAppear,
                isEpisodeRoute: isEpisodeRoute,
                artworkAction: {
                    let playbackDiagnosticID: String?
                    #if DEBUG
                    playbackDiagnosticID = String(UUID().uuidString.prefix(8))
                    MediaPlayerManager.logEpisodePlayback(
                        playbackDiagnosticID,
                        event: "artwork-activation episodeID=\(episode.id ?? "unknown") detailsCoordinator=\(router.router.navigationCoordinator?.debugDiagnosticID ?? "unknown")"
                    )
                    #else
                    playbackDiagnosticID = nil
                    #endif

                    guard let provider = episode.getPlaybackItemProvider(userSession: nil) else {
                        #if DEBUG
                        MediaPlayerManager.logEpisodePlayback(
                            playbackDiagnosticID,
                            event: "provider-unavailable episodeID=\(episode.id ?? "unknown")"
                        )
                        #endif
                        return
                    }

                    router.route(
                        to: .videoPlayer(
                            provider: provider,
                            queue: EpisodeMediaPlayerQueue(
                                episode: episode,
                                playbackDiagnosticID: playbackDiagnosticID
                            )
                        )
                    )
                },
                contentAction: {
                    router.route(to: .item(item: episode), in: namespace)
                },
                contextMenuItem: episode
            ) {
                ImageView(episode.landscapeImageSources(
                    environment: .init(maxWidth: 250)
                ))
                .failure {
                    SystemImageContentView(systemName: episode.systemImage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    overlayView
                }
                .contentShape(.contextMenuPreview, Rectangle())
                .posterStyle(.landscape)
                .subtleShadow()
                .matchedTransitionSource(id: "item", in: namespace)
            }
        }
    }

    struct EpisodeStateCard: View {

        let title: String
        let subHeader: String
        let content: String
        let systemImage: String?
        let action: () -> Void

        var body: some View {
            EpisodeCardLayout(
                header: title,
                subHeader: subHeader,
                content: content,
                artworkAction: action,
                contentAction: action
            ) {
                Rectangle()
                    .fill(.complexSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if let systemImage {
                            RelativeSystemImageView(systemName: systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .posterStyle(.landscape)
                    .subtleShadow()
            }
        }
    }

    private struct EpisodeCardLayout<Artwork: View>: View {

        private enum FocusedElement: Hashable {
            case artwork
            case content
        }

        @FocusState
        private var focusedElement: FocusedElement?

        #if os(tvOS)
        @Environment(\.screenTheme)
        private var screenTheme
        #endif

        let header: String
        let subHeader: String
        let content: String
        let artworkFocusTarget: EpisodeRouteIntent.FocusTarget?
        let onArtworkFocusActionAppear: (() -> Void)?
        let isEpisodeRoute: Bool
        let artworkAction: () -> Void
        let contentAction: () -> Void
        let contextMenuItem: BaseItemDto?
        let artwork: Artwork

        init(
            header: String,
            subHeader: String,
            content: String,
            artworkFocusTarget: EpisodeRouteIntent.FocusTarget? = nil,
            onArtworkFocusActionAppear: (() -> Void)? = nil,
            isEpisodeRoute: Bool = false,
            artworkAction: @escaping () -> Void,
            contentAction: @escaping () -> Void,
            contextMenuItem: BaseItemDto? = nil,
            @ViewBuilder artwork: () -> Artwork
        ) {
            self.header = header
            self.subHeader = subHeader
            self.content = content
            self.artworkFocusTarget = artworkFocusTarget
            self.onArtworkFocusActionAppear = onArtworkFocusActionAppear
            self.isEpisodeRoute = isEpisodeRoute
            self.artworkAction = artworkAction
            self.contentAction = contentAction
            self.contextMenuItem = contextMenuItem
            self.artwork = artwork()
        }

        @ViewBuilder
        private var artworkButton: some View {
            let button = Button(action: artworkAction) {
                artwork
                    #if os(tvOS)
                        .overlay {
                            Rectangle()
                                .stroke(
                                    focusedElement == .artwork ? screenTheme.focus.keylineOnSurface.swiftUIColor : .clear,
                                    lineWidth: 3
                                )
                        }
                        .shadow(
                            color: focusedElement == .artwork ? screenTheme.focus.glow.swiftUIColor.opacity(0.38) : .clear,
                            radius: focusedElement == .artwork ? 22 : 0
                        )
                        .animation(.easeOut(duration: 0.16), value: focusedElement)
                    #endif
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.card)
            #if os(tvOS)
            .buttonBorderShape(.roundedRectangle(radius: 0))
            #endif
            .focused($focusedElement, equals: .artwork)

            if let artworkFocusTarget {
                let focusedButton = button.coordinatedFocus(
                    artworkFocusTarget.coordinatorID,
                    consumesRequestOnAcquisition: true
                )
                .onAppear {
                    onArtworkFocusActionAppear?()
                }

                if let contextMenuItem {
                    focusedButton.posterContextMenu(for: contextMenuItem) {
                        artwork
                    }
                } else {
                    focusedButton
                }
            } else if let contextMenuItem {
                button.posterContextMenu(for: contextMenuItem) {
                    artwork
                }
            } else {
                button
            }
        }

        var body: some View {
            VStack(alignment: .leading) {
                artworkButton

                Button(action: contentAction) {
                    EpisodeMetadataView(
                        header: header,
                        subHeader: subHeader,
                        content: content
                    )
                }
                .foregroundStyle(.primary, .secondary)
                #if os(tvOS)
                .buttonStyle(
                    EpisodeContentButtonStyle(
                        showsMaterial: focusedElement != nil,
                        isFocused: focusedElement == .content
                    )
                )
                #endif
                .focused($focusedElement, equals: .content)
            }
            .focusSection()
            .defaultFocus(
                $focusedElement,
                isEpisodeRoute && artworkFocusTarget == nil ? nil : .artwork,
                priority: .userInitiated
            )
        }
    }

    private struct EpisodeMetadataView: View {

        let header: String
        let subHeader: String
        let content: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(subHeader)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(header)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                SeeMoreText(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if os(tvOS)
    private struct EpisodeContentButtonStyle: ButtonStyle {

        @Environment(\.screenTheme)
        private var screenTheme

        let showsMaterial: Bool
        let isFocused: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(28)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(height: 200)
                .backport
                .glassEffect(
                    showsMaterial ? .regular : .identity,
                    in: .rect
                )
                .overlay {
                    Rectangle()
                        .stroke(
                            isFocused ? screenTheme.focus.keylineOnSurface.swiftUIColor : .clear,
                            lineWidth: 3
                        )
                }
                .scaleEffect(isFocused ? 1.05 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .brightness(isFocused ? 0.04 : 0)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .shadow(
                    color: isFocused ? screenTheme.focus.glow.swiftUIColor.opacity(0.3) : .clear,
                    radius: isFocused ? 20 : 0
                )
                .animation(.easeInOut(duration: 0.2), value: showsMaterial)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    #endif
}
