//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct Subtitles: View {

        let showsCurrentSelection: Bool

        init(showsCurrentSelection: Bool = false) {
            self.showsCurrentSelection = showsCurrentSelection
        }

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var selectedSubtitleStreamIndex: Int?

        private var systemImage: String {
            if selectedSubtitleStreamIndex == nil {
                VideoPlayerActionButton.subtitles.secondarySystemImage
            } else {
                VideoPlayerActionButton.subtitles.systemImage
            }
        }

        @ViewBuilder
        private func content(playbackItem: MediaPlayerItem) -> some View {
            Picker(L10n.subtitles, selection: $selectedSubtitleStreamIndex) {
                ForEach(playbackItem.subtitleStreams.prepending(.none), id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            }
        }

        private func selectionTitle(playbackItem: MediaPlayerItem) -> String {
            guard let selectedSubtitleStreamIndex,
                  selectedSubtitleStreamIndex != -1,
                  let selectedSubtitleStream = playbackItem.subtitleStreams.first(where: { $0.index == selectedSubtitleStreamIndex })
            else { return L10n.none }

            if let displayTitle = selectedSubtitleStream.displayTitle, !displayTitle.isEmpty {
                return displayTitle
            }

            return selectedSubtitleStream.language ?? L10n.unknown
        }

        @ViewBuilder
        private func menuLabel(playbackItem: MediaPlayerItem) -> some View {
            if showsCurrentSelection {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectionTitle(playbackItem: playbackItem))
                        .font(.headline)
                        .lineLimit(2)

                    Text(L10n.subtitles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Label(L10n.subtitles, systemImage: systemImage)
            }
        }

        var body: some View {
            if let playbackItem = manager.playbackItem {
                Menu {
                    if isInMenu {
                        content(playbackItem: playbackItem)
                    } else {
                        Section(L10n.subtitles) {
                            content(playbackItem: playbackItem)
                        }
                    }
                } label: {
                    menuLabel(playbackItem: playbackItem)
                }
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
                .videoPlayerActionButtonTransition()
                .assign(playbackItem.$selectedSubtitleStreamIndex, to: $selectedSubtitleStreamIndex)
                .onChange(of: selectedSubtitleStreamIndex) {
                    playbackItem.selectedSubtitleStreamIndex = selectedSubtitleStreamIndex
                }
            }
        }
    }
}
