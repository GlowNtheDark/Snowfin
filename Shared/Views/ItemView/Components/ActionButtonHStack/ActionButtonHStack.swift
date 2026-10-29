//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionButtonHStack: View {

        @ObservedObject
        var provider: ItemContentGroupProvider

        @Router
        private var router

        #if os(tvOS)
        @Environment(\.screenTheme)
        private var screenTheme
        #endif

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        #if os(tvOS)
        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @State
        private var markUnwatchedError: Error?

        private var hasPendingEpisodeRouteFocus: Bool {
            provider.episodeRouteIntent != nil && focusCoordinator.hasPendingFocusRequest
        }
        #endif

        private var hasTrailers: Bool {
            if enabledTrailers.contains(.local), provider.localTrailers.isNotEmpty {
                return true
            }

            if enabledTrailers.contains(.external), provider.item.remoteTrailers?.isNotEmpty == true {
                return true
            }

            return false
        }

        private var shouldShowTrailers: Bool {
            #if os(tvOS)
            provider.item.type != .series && hasTrailers
            #else
            hasTrailers
            #endif
        }

        private var playedTint: Color {
            #if os(tvOS)
            screenTheme.selection.indicator.swiftUIColor
            #else
            .jellyfinPurple
            #endif
        }

        private func playedForeground(isPlayed: Bool) -> Color {
            #if os(tvOS)
            isPlayed ? screenTheme.actions.primaryForeground.swiftUIColor : screenTheme.actions.secondaryForeground.swiftUIColor
            #else
            .primary
            #endif
        }

        @ViewBuilder
        private func materialLabel(
            _ title: String,
            systemImage: String,
            isHighlighted: Bool = false,
            tint: Color,
            foregroundColor: Color,
            isRotated: Bool = false
        ) -> some View {
            #if os(tvOS)
            let inactiveTint = screenTheme.actions.secondaryFill.swiftUIColor
            let inactiveForeground = screenTheme.actions.secondaryForeground.swiftUIColor
            #else
            let inactiveTint = Color.gray.opacity(0.3)
            let inactiveForeground = foregroundColor
            #endif

            #if os(tvOS)
            let shape: Rectangle = .rect
            #else
            let shape: RoundedRectangle = .rect(cornerRadius: 10, style: .circular)
            #endif

            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .rotationEffect(isRotated ? .degrees(90) : .degrees(0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: isHighlighted ? tint : inactiveTint,
                    foregroundColor: isHighlighted ? foregroundColor : inactiveForeground
                ),
                in: shape
            )
            #if os(tvOS)
            .overlay {
                if !isHighlighted {
                    shape
                        .stroke(screenTheme.actions.secondaryBoundary.swiftUIColor, lineWidth: 1)
                }
            }
            #endif
        }

        var body: some View {
            #if os(tvOS)
            if provider.item.type == .movie, provider.item.canBePlayed {
                let isPlayed = provider.item.userData?.isPlayed == true

                Button {
                    Task { await provider.toggleIsPlayed() }
                } label: {
                    materialLabel(
                        L10n.played,
                        systemImage: "checkmark",
                        isHighlighted: isPlayed,
                        tint: playedTint,
                        foregroundColor: playedForeground(isPlayed: isPlayed)
                    )
                }
                .frame(height: 64)
                .labelStyle(.titleAndIcon)
                .buttonStyle(BasicHoverButtonStyle())
                .font(.headline)
                .fontWeight(.semibold)
            } else if (UIDevice.isTV && provider.item.canEdit) ||
                provider.item.canBePlayed ||
                provider.item.canBeFavorited ||
                shouldShowTrailers
            {
                contentView
            }
            #else
            if (UIDevice.isTV && provider.item.canEdit) ||
                provider.item.canBePlayed ||
                provider.item.canBeFavorited ||
                shouldShowTrailers
            {
                contentView
            }
            #endif
        }

        @ViewBuilder
        private var contentView: some View {
            let content = HStack(alignment: .center, spacing: UIDevice.isTV ? 30 : 10) {

                #if os(tvOS)
                if provider.item.type == .series {
                    Button {
                        Task {
                            do {
                                try await provider.markSeriesUnwatched()
                            } catch {
                                markUnwatchedError = error
                            }
                        }
                    } label: {
                        materialLabel(
                            L10n.markAsUnplayed,
                            systemImage: "checkmark.circle",
                            tint: playedTint,
                            foregroundColor: .primary
                        )
                    }
                    .frame(width: 520, height: 75)
                    .labelStyle(.titleAndIcon)
                    .disabled(provider.isMarkingSeriesUnwatched)
                    .disabled(hasPendingEpisodeRouteFocus)
                    .accessibilityIdentifier("show-details-mark-unwatched")
                }
                #endif

                // MARK: Played

                if provider.item.canBePlayed {
                    let isPlayed = provider.item.userData?.isPlayed == true

                    Button {
                        Task { await provider.toggleIsPlayed() }
                    } label: {
                        materialLabel(
                            L10n.played,
                            systemImage: "checkmark",
                            isHighlighted: isPlayed,
                            tint: playedTint,
                            foregroundColor: playedForeground(isPlayed: isPlayed)
                        )
                    }
                    #if !os(tvOS)
                    .foregroundStyle(.primary, .secondary)
                    #else
                        .disabled(hasPendingEpisodeRouteFocus)
                    #endif
                }

                // MARK: Favorite

                if provider.item.canBeFavorited {
                    let isFavorited = provider.item.userData?.isFavorite == true

                    Button {
                        Task { await provider.toggleIsFavorite() }
                    } label: {
                        materialLabel(
                            L10n.favorited,
                            systemImage: isFavorited ? "heart.fill" : "heart",
                            isHighlighted: isFavorited,
                            tint: .pink,
                            foregroundColor: .primary
                        )
                    }
                    #if !os(tvOS)
                    .foregroundStyle(.primary, .secondary)
                    #else
                        .disabled(hasPendingEpisodeRouteFocus)
                    #endif
                    .isSelected(isFavorited)
                }

                // MARK: Trailer

                if shouldShowTrailers {
                    TrailerMenu(
                        localTrailers: provider.localTrailers,
                        externalTrailers: provider.item.remoteTrailers ?? []
                    ) {
                        materialLabel(
                            L10n.trailers,
                            systemImage: "movieclapper",
                            tint: .pink,
                            foregroundColor: .primary
                        )
                    }
                    #if os(tvOS)
                    .disabled(hasPendingEpisodeRouteFocus)
                    #endif
                }

                // MARK: tvOS Options

                #if os(tvOS)
                if provider.item.canEdit || provider.item.canDeleteItem {
                    EditItemMenu(item: provider.item) {
                        materialLabel(
                            L10n.advanced,
                            systemImage: "ellipsis",
                            tint: .clear,
                            foregroundColor: .primary,
                            isRotated: true
                        )
                        .frame(
                            width: provider.item.type == .episode ? 60 : nil,
                            height: provider.item.type == .episode ? 75 : nil
                        )
                    }
                    .frame(width: 60)
                    .foregroundStyle(.primary, .secondary)
                    .disabled(hasPendingEpisodeRouteFocus)
                }
                #endif
            }
            .frame(height: UIDevice.isTV ? 75 : 44)
            .labelStyle(.iconOnly)
            .font(.title3)
            .fontWeight(.semibold)
            #if os(tvOS)
            .errorMessage($markUnwatchedError)
            #endif

            #if os(tvOS)
            if provider.item.type == .episode {
                content
                    .buttonStyle(BasicHoverButtonStyle(scalesOnInteraction: false))
                    .buttonBorderShape(.roundedRectangle(radius: 0))
            } else {
                content.buttonStyle(BasicHoverButtonStyle())
            }
            #else
            content.buttonStyle(BasicHoverButtonStyle())
            #endif
        }
    }
}
