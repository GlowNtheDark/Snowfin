//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct PosterIndicatorsOverlay: View {

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    @Environment(\.viewContext)
    private var viewContext

    #if os(tvOS)
    @Environment(\.screenTheme)
    private var screenTheme

    @Environment(\.homeFocusTile)
    private var homeFocusTile

    private var usesSemanticPalette: Bool {
        viewContext.contains(.isMovieDetails) ||
            viewContext.contains(.isSearchResults) ||
            viewContext.contains(.isMoviesTVLibrary) ||
            viewContext.contains(.isPlaybackOverlay) ||
            homeFocusTile != nil
    }
    #endif

    private var semanticPalette: ThemePalette? {
        #if os(tvOS)
        usesSemanticPalette ? screenTheme : nil
        #else
        nil
        #endif
    }

    let item: BaseItemDto
    let posterDisplayType: PosterDisplayType

    private var indicators: PosterIndicator {
        posterConfiguration.indicators
    }

    private var indicatorSize: CGFloat {
        UIDevice.isTV ? 45 : 25
    }

    /// Jellyfin's user state is authoritative for watched treatment; resume
    /// progress must not promote an item to watched.
    private var isWatched: Bool {
        item.userData?.isPlayed == true
    }

    private var showsUnplayedIndicator: Bool {
        indicators.contains(.unplayed) &&
            item.canBePlayed &&
            !item.isLiveStream &&
            item.userData?.isPlayed == false &&
            (item.userData?.playbackPositionTicks ?? 0) == 0
    }

    private var showsProgressIndicator: Bool {
        indicators.contains(.progress) &&
            item.progressLabel != nil &&
            (!isWatched || item.type == .episode)
    }

    private var showsCompletedProgressIndicator: Bool {
        indicators.contains(.played) &&
            item.canBePlayed &&
            !item.isLiveStream &&
            isWatched &&
            !(item.type == .episode && showsProgressIndicator)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsUnplayedIndicator {
                    UnplayedIndicator(
                        count: posterConfiguration.unplayedStyle == .count ? item.userData?.unplayedItemCount : nil,
                        semanticPalette: semanticPalette
                    )
                    .frame(height: indicatorSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                HStack(spacing: 5) {
                    if indicators.contains(.favorited), item.userData?.isFavorite == true {
                        FavoriteIndicator()
                            .frame(width: indicatorSize, height: indicatorSize)
                    }

                    #if os(iOS)
                    if indicators.contains(.played),
                       item.canBePlayed,
                       !item.isLiveStream,
                       isWatched
                    {
                        PlayedIndicator()
                            .frame(width: indicatorSize, height: indicatorSize)
                    }
                    #endif
                }
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(tvOS)
            if showsProgressIndicator || showsCompletedProgressIndicator {
                ProgressIndicator(
                    title: showsCompletedProgressIndicator ? nil : item.progressLabel,
                    progress: showsCompletedProgressIndicator ? 1 : item.progressPercentage ?? 0,
                    posterDisplayType: posterDisplayType,
                    isCompleted: showsCompletedProgressIndicator,
                    semanticPalette: semanticPalette
                )
                .zIndex(5)
            }
            #else
            if showsProgressIndicator {
                ProgressIndicator(
                    title: item.progressLabel,
                    progress: item.progressPercentage ?? 0,
                    posterDisplayType: posterDisplayType,
                    isCompleted: false
                )
                .zIndex(5)
            }
            #endif
        }
    }
}

struct PosterSelectionOverlay: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.isSelected)
    private var isSelected

    @Environment(\.viewContext)
    private var viewContext

    #if os(tvOS)
    @Environment(\.screenTheme)
    private var screenTheme

    @Environment(\.homeFocusTile)
    private var homeFocusTile
    #endif

    private var selectionColor: Color {
        #if os(tvOS)
        if viewContext.contains(.isMovieDetails) ||
            viewContext.contains(.isSearchResults) ||
            viewContext.contains(.isMoviesTVLibrary) ||
            viewContext.contains(.isPlaybackOverlay) ||
            homeFocusTile != nil
        {
            return screenTheme.selection.indicator.swiftUIColor
        }
        #endif
        return accentColor
    }

    var body: some View {
        if isSelected {
            ContainerRelativeShape()
                .stroke(selectionColor, lineWidth: UIDevice.isTV ? 12 : 8)
                .clipped()
        }
    }
}
