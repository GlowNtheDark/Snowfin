//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct Audio: View {

        let showsCurrentSelection: Bool

        init(showsCurrentSelection: Bool = false) {
            self.showsCurrentSelection = showsCurrentSelection
        }

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var selectedAudioStreamIndex: Int?

        private var systemImage: String {
            if selectedAudioStreamIndex == nil {
                VideoPlayerActionButton.audio.secondarySystemImage
            } else {
                VideoPlayerActionButton.audio.systemImage
            }
        }

        @ViewBuilder
        private func content(playbackItem: MediaPlayerItem) -> some View {
            Picker(selection: $selectedAudioStreamIndex) {
                ForEach(playbackItem.audioStreams, id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            } label: {
                Text(L10n.audio)

                if let selectedAudioStream = playbackItem.audioStreams.first(where: { $0.index == selectedAudioStreamIndex }) {
                    Text(selectedAudioStream.displayTitle ?? L10n.unknown)
                }
            }
        }

        private func selectionTitle(playbackItem: MediaPlayerItem) -> String {
            guard let selectedAudioStream = playbackItem.audioStreams.first(where: { $0.index == selectedAudioStreamIndex }) else {
                return L10n.none
            }

            if let displayTitle = selectedAudioStream.displayTitle, !displayTitle.isEmpty {
                return displayTitle
            }

            let details = [
                selectedAudioStream.language,
                selectedAudioStream.codec?.uppercased(),
                selectedAudioStream.channelLayout ?? selectedAudioStream.channels?.description,
            ]
                .compactMap(\.self)
                .filter { !$0.isEmpty }

            return details.isEmpty ? L10n.unknown : details.joined(separator: " • ")
        }

        @ViewBuilder
        private func menuLabel(playbackItem: MediaPlayerItem) -> some View {
            if showsCurrentSelection {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectionTitle(playbackItem: playbackItem))
                        .font(.headline)
                        .lineLimit(2)

                    Text(L10n.audio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Label(L10n.audio, systemImage: systemImage)
            }
        }

        var body: some View {
            if let playbackItem = manager.playbackItem {
                Menu {
                    if isInMenu {
                        content(playbackItem: playbackItem)
                    } else {
                        Section(L10n.audio) {
                            content(playbackItem: playbackItem)
                        }
                    }
                } label: {
                    menuLabel(playbackItem: playbackItem)
                }
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary, .secondary)
                .videoPlayerActionButtonTransition()
                .assign(playbackItem.$selectedAudioStreamIndex, to: $selectedAudioStreamIndex)
                .onChange(of: selectedAudioStreamIndex) {
                    playbackItem.selectedAudioStreamIndex = selectedAudioStreamIndex
                }
            }
        }
    }
}
