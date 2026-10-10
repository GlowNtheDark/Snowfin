//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct HUDMetadata: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        private var title: String {
            manager.item.seriesName ?? manager.item.parentTitle ?? manager.item.displayTitle
        }

        private var episodeTitle: String {
            let fallbackTitle = manager.item.episodeLocator
            let itemTitle = manager.item.name?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let itemTitle,
                  !itemTitle.isEmpty,
                  itemTitle != fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return fallbackTitle ?? manager.item.displayTitle
            }

            return itemTitle
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                if manager.item.type == .episode,
                   let seasonEpisodeLabel = manager.item.seasonEpisodeLabel
                {
                    Text(seasonEpisodeLabel)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                if manager.item.type == .episode,
                   episodeTitle != title
                {
                    Text(episodeTitle)
                        .font(.title3)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct TransportButtonStyle: ButtonStyle {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.isFocused)
        private var isFocused

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(isFocused ? accentColor.overlayColor : .white)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Rectangle()
                                .fill(isFocused ? accentColor : Color.snowfinDeepNavy.opacity(0.62))
                        }
                }
                .overlay {
                    Rectangle()
                        .stroke(
                            isFocused ? Color.white.opacity(0.8) : Color.white.opacity(0.16),
                            lineWidth: isFocused ? 2 : 1
                        )
                }
                .shadow(
                    color: isFocused ? accentColor.opacity(0.34) : .clear,
                    radius: isFocused ? 16 : 0
                )
                .scaleEffect(configuration.isPressed ? 0.96 : isFocused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.12), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
