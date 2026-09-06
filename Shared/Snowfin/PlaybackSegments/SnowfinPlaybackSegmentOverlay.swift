//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

#if os(tvOS)
struct SnowfinPlaybackSegmentOverlay: View {
    private let snowfinIceBlue = Color(red: 46 / 255, green: 168 / 255, blue: 255 / 255)
    private let snowfinDeepNavy = Color(red: 4 / 255, green: 20 / 255, blue: 38 / 255)

    private enum FocusedAction: Hashable {
        case intro
        case keepWatching
        case playNext
    }

    @ObservedObject
    var coordinator: SnowfinPlaybackSegmentCoordinator

    @ObservedObject
    var containerState: VideoPlayerContainerState

    @FocusState
    private var focusedAction: FocusedAction?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if coordinator.isOverlayPresented, let presentation = coordinator.presentation {
                switch presentation.kind {
                case .intro:
                    Button("Skip Intro") {
                        coordinator.skipIntro()
                    }
                    .focused($focusedAction, equals: .intro)
                    .buttonStyle(.borderedProminent)
                    .tint(snowfinIceBlue)
                    .controlSize(.large)
                    .shadow(color: snowfinIceBlue.opacity(0.35), radius: 18)
                    .padding(80)

                case .nextEpisode, .countdown:
                    nextEpisodeOverlay(presentation)
                        .padding(70)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .focusSection()
        .onChange(of: coordinator.isOverlayPresented) {
            updateFocus(for: coordinator.presentation)
        }
        .onAppear {
            updateFocus(for: coordinator.presentation)
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.isOverlayPresented)
    }

    private func updateFocus(for presentation: SnowfinPlaybackSegmentCoordinator.Presentation?) {
        containerState.isPresentingSegmentOverlay = presentation != nil

        guard let presentation else {
            focusedAction = nil
            return
        }

        Task { @MainActor in
            await Task.yield()
            switch presentation.kind {
            case .intro:
                focusedAction = .intro
            case .nextEpisode:
                focusedAction = .playNext
            case .countdown:
                focusedAction = .playNext
            }
        }
    }

    @ViewBuilder
    private func nextEpisodeOverlay(_ presentation: SnowfinPlaybackSegmentCoordinator.Presentation) -> some View {
        if let item = presentation.item {
            HStack(spacing: 28) {
                PosterImage(item: item, type: .landscape)
                    .frame(width: 330)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Up Next")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(item.displayTitle)
                        .font(.title2.bold())
                        .lineLimit(2)

                    if let locator = item.episodeLocator {
                        Text(locator)
                            .foregroundStyle(.secondary)
                    }

                    if let remaining = presentation.remainingSeconds {
                        Text("Playing in \(remaining) seconds")
                            .font(.title3.monospacedDigit())
                    }

                    HStack(spacing: 18) {
                        Button("Play Next") {
                            coordinator.playNextEpisode()
                        }
                        .focused($focusedAction, equals: .playNext)
                        .buttonStyle(.borderedProminent)
                        .tint(snowfinIceBlue)

                        if presentation.remainingSeconds != nil {
                            Button("Keep Watching") {
                                coordinator.keepWatching()
                            }
                            .focused($focusedAction, equals: .keepWatching)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(width: 430, alignment: .leading)
            }
            .padding(28)
            .background {
                Rectangle()
                    .fill(snowfinDeepNavy.opacity(0.92))
                    .overlay {
                        Rectangle()
                            .stroke(snowfinIceBlue.opacity(0.45), lineWidth: 2)
                    }
                    .shadow(color: snowfinIceBlue.opacity(0.22), radius: 24)
            }
        }
    }
}
#endif
