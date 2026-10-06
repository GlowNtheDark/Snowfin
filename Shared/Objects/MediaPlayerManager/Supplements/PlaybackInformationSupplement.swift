//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

// TODO: have proxies be a `PlaybackInformationProvider`
//       - be labeled pair information
// TODO: tvOS: use material background

class PlaybackInformationSupplement: ObservableObject, MediaPlayerSupplement {

    let displayTitle: String = L10n.session
    let itemID: String
    let provider: PlaybackInformationProvider

    var id: String {
        "PlaybackInformation-\(itemID)"
    }

    init(itemID: String) {
        self.itemID = itemID
        self.provider = .init(itemID: itemID)
    }

    var videoPlayerBody: some PlatformView {
        OverlayView(viewModel: provider)
    }
}

extension PlaybackInformationSupplement {

    private struct OverlayView: PlatformView {

        #if os(tvOS)
        private enum TechnicalDetailsColumn: Hashable {
            case primary
            case secondary
        }

        private enum TechnicalDetailsTarget: Hashable {
            case primaryRow(String)
            case secondaryRow(String)
        }

        private struct DiagnosticRow: Identifiable {
            let id: String
            let label: String?
            let value: String
            var isSecondary = false
        }

        private struct DiagnosticGroup: Identifiable {
            let id: String
            let title: String
            let rows: [DiagnosticRow]
        }

        @Environment(\.safeAreaInsets)
        private var safeAreaInsets: EdgeInsets

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ObservedObject
        var viewModel: PlaybackInformationProvider

        @FocusState
        private var focusedTechnicalDetailsTarget: TechnicalDetailsTarget?
        #endif

        private var mediaSource: MediaSourceInfo? {
            manager.playbackItem?.mediaSource
        }

        private var videoStream: MediaStream? {
            manager.playbackItem?.videoStreams.first
        }

        private var audioStream: MediaStream? {
            guard let playbackItem = manager.playbackItem else { return nil }
            if let selectedIndex = playbackItem.selectedAudioStreamIndex {
                return playbackItem.audioStreams.first { $0.index == selectedIndex }
            }
            return playbackItem.audioStreams.first
        }

        #if os(tvOS)
        private var tvOSTechnicalDetailsColumns: [[DiagnosticGroup]] {
            var playbackRows = [
                DiagnosticRow(
                    id: "video-player",
                    label: L10n.videoPlayer,
                    value: Defaults[.VideoPlayer.videoPlayerType].displayTitle
                ),
            ]

            if let playMethod = viewModel.currentSession?.playMethodDisplayTitle {
                playbackRows.append(.init(id: "method", label: L10n.method, value: playMethod))
            } else if let mediaSource {
                let method = mediaSource.transcodingURL == nil
                    ? PlayMethod.directPlay.displayTitle
                    : PlayMethod.transcode.displayTitle
                playbackRows.append(.init(id: "method", label: L10n.method, value: method))
            }

            if let requestedBitrate = manager.playbackItem?.requestedBitrate {
                playbackRows.append(.init(id: "quality", label: L10n.quality, value: requestedBitrate.displayTitle))
            }

            if let playSessionID = manager.playbackItem?.playSessionID, !playSessionID.isEmpty {
                // swiftlint:disable:next hard_coded_display_string
                playbackRows.append(.init(id: "play-session", label: "Play Session ID", value: playSessionID))
            }

            if let transcodingInfo = viewModel.currentSession?.transcodingInfo {
                if let hwAccel = transcodingInfo.hardwareAccelerationType {
                    playbackRows.append(.init(id: "hardware-acceleration", label: L10n.hardwareAcceleration, value: hwAccel.rawValue))
                }
                if let completion = transcodingInfo.completionPercentage {
                    playbackRows.append(.init(id: "transcode-progress", label: L10n.transcodeProgress, value: "\(Int(completion))%"))
                }
            }

            var videoRows: [DiagnosticRow] = []
            if let width = videoStream?.width, let height = videoStream?.height {
                videoRows.append(.init(
                    id: "resolution",
                    label: L10n.videoResolution,
                    value: height.description.multiply(by: width.description)
                ))
            }
            if let codec = videoStream?.codec {
                let display = videoStream?.profile.map { "\(codec.uppercased()) \($0)" } ?? codec.uppercased()
                videoRows.append(.init(id: "codec", label: L10n.videoCodec, value: display))
            }
            if let bitRate = videoStream?.bitRate {
                videoRows.append(.init(id: "bitrate", label: L10n.videoBitRate, value: bitRate.formatted(.bitRate)))
            }
            if let videoRangeType = videoStream?.videoRangeType {
                videoRows.append(.init(id: "range", label: L10n.videoRangeType, value: videoRangeType.rawValue))
            }
            if let proxy = manager.proxy as? any VideoMediaPlayerProxy {
                videoRows.append(.init(id: "dropped-frames", label: L10n.droppedFrames, value: proxy.droppedFrames.value.description))
                videoRows.append(.init(id: "corrupted-frames", label: L10n.corruptedFrames, value: proxy.corruptedFrames.value.description))
            }

            var audioRows: [DiagnosticRow] = []
            if let audioStream {
                if let displayTitle = audioStream.displayTitle, !displayTitle.isEmpty {
                    audioRows.append(.init(id: "audio-track", label: L10n.audio, value: displayTitle))
                }
                if let codec = audioStream.codec {
                    audioRows.append(.init(id: "codec", label: L10n.audioCodec, value: codec.uppercased()))
                }
                if let channelLayout = audioStream.channelLayout {
                    audioRows.append(.init(id: "channels", label: L10n.channels, value: channelLayout))
                } else if let channels = audioStream.channels {
                    audioRows.append(.init(id: "channels", label: L10n.channels, value: channels.description))
                }
                if let bitRate = audioStream.bitRate {
                    audioRows.append(.init(id: "bitrate", label: L10n.audioBitrate, value: bitRate.formatted(.bitRate)))
                }
                if let sampleRate = audioStream.sampleRate {
                    audioRows.append(.init(id: "sample-rate", label: L10n.audioSampleRate, value: "\(sampleRate) Hz"))
                }
            }

            var sourceRows: [DiagnosticRow] = []
            if let mediaSource {
                if let name = mediaSource.name, !name.isEmpty {
                    sourceRows.append(.init(id: "name", label: L10n.name, value: name))
                }
                if let deliveryProtocol = mediaSource.protocol {
                    sourceRows.append(.init(id: "protocol", label: L10n.source, value: deliveryProtocol.rawValue.uppercased()))
                }
                if let transcodingSubProtocol = mediaSource.transcodingSubProtocol {
                    sourceRows.append(.init(
                        id: "transcode-protocol",
                        label: L10n.protocol,
                        value: transcodingSubProtocol.rawValue.uppercased()
                    ))
                }
                if let container = mediaSource.container {
                    sourceRows.append(.init(id: "container", label: L10n.container, value: container))
                }
                if let size = mediaSource.size {
                    sourceRows.append(.init(id: "size", label: L10n.size, value: Int64(size).formatted(.byteCount(style: .file))))
                }
                if let bitrate = mediaSource.bitrate {
                    sourceRows.append(.init(id: "bitrate", label: L10n.bitrate, value: bitrate.formatted(.bitRate)))
                }
            }

            var streamRows: [DiagnosticRow] = []
            if let transcodingInfo = viewModel.currentSession?.transcodingInfo {
                if let videoCodec = transcodingInfo.videoCodec {
                    streamRows.append(.init(
                        id: "video-codec",
                        label: L10n.videoCodec,
                        value: transcodingInfo.isVideoDirect == true
                            ? "\(videoCodec.uppercased()) (\(L10n.direct))"
                            : videoCodec.uppercased()
                    ))
                }
                if let audioCodec = transcodingInfo.audioCodec {
                    streamRows.append(.init(
                        id: "audio-codec",
                        label: L10n.audioCodec,
                        value: transcodingInfo.isAudioDirect == true
                            ? "\(audioCodec.uppercased()) (\(L10n.direct))"
                            : audioCodec.uppercased()
                    ))
                }
                if let hwAccel = transcodingInfo.hardwareAccelerationType {
                    streamRows.append(.init(id: "hardware-acceleration", label: L10n.hardwareAcceleration, value: hwAccel.rawValue))
                }
                if let completion = transcodingInfo.completionPercentage {
                    streamRows.append(.init(id: "transcode-progress", label: L10n.transcodeProgress, value: "\(Int(completion))%"))
                }
            }

            let transcodeReasons = viewModel.currentSession?.transcodingInfo?.transcodeReasons ?? []
            let transcodeReasonRows = transcodeReasons.enumerated().map { index, reason in
                DiagnosticRow(id: "transcode-reason-\(index)", label: nil, value: reason.displayTitle, isSecondary: true)
            }

            let primaryGroups = [
                DiagnosticGroup(id: "playback", title: L10n.mediaPlayback, rows: playbackRows),
                DiagnosticGroup(id: "video", title: L10n.video, rows: videoRows),
            ].filter { !$0.rows.isEmpty }

            let secondaryGroups = [
                DiagnosticGroup(id: "audio", title: L10n.audio, rows: audioRows),
                DiagnosticGroup(id: "source", title: L10n.source, rows: sourceRows),
                DiagnosticGroup(
                    id: "streaming",
                    title: viewModel.currentSession?.playMethodDisplayTitle.map { L10n.streamInfoWithMethod($0) } ?? L10n.streamInfo,
                    rows: streamRows
                ),
                DiagnosticGroup(id: "transcode-reasons", title: L10n.transcodeReasons, rows: transcodeReasonRows),
            ].filter { !$0.rows.isEmpty }

            return [primaryGroups, secondaryGroups]
        }

        private func technicalDetailsTarget(
            for row: DiagnosticRow,
            in column: TechnicalDetailsColumn
        ) -> TechnicalDetailsTarget {
            switch column {
            case .primary:
                .primaryRow(row.id)
            case .secondary:
                .secondaryRow(row.id)
            }
        }

        private func rows(in column: TechnicalDetailsColumn) -> [DiagnosticRow] {
            let columnIndex = column == .primary ? 0 : 1
            return tvOSTechnicalDetailsColumns[columnIndex].flatMap(\.rows)
        }

        private func moveTechnicalDetailsFocus(
            from target: TechnicalDetailsTarget,
            direction: MoveCommandDirection
        ) {
            let column: TechnicalDetailsColumn
            let rowID: String
            switch target {
            case let .primaryRow(id):
                column = .primary
                rowID = id
            case let .secondaryRow(id):
                column = .secondary
                rowID = id
            }

            let columnRows = rows(in: column)
            guard let index = columnRows.firstIndex(where: { $0.id == rowID }) else { return }

            switch direction {
            case .up:
                guard index > 0 else {
                    focusedTechnicalDetailsTarget = nil
                    containerState.isTechnicalDetailsContentFocused = false
                    containerState.isPlaybackDropdownTopNavigationFocused = true
                    containerState.playbackDropdownFocusRequest = .section(2)
                    return
                }
                focusedTechnicalDetailsTarget = technicalDetailsTarget(for: columnRows[index - 1], in: column)

            case .down:
                guard columnRows.indices.contains(index + 1) else { return }
                focusedTechnicalDetailsTarget = technicalDetailsTarget(for: columnRows[index + 1], in: column)

            case .left, .right:
                let otherColumn: TechnicalDetailsColumn = column == .primary ? .secondary : .primary
                let otherRows = rows(in: otherColumn)
                guard !otherRows.isEmpty else { return }
                let otherIndex = min(index, otherRows.count - 1)
                focusedTechnicalDetailsTarget = technicalDetailsTarget(for: otherRows[otherIndex], in: otherColumn)

            @unknown default:
                break
            }
        }

        private func diagnosticRow(
            _ row: DiagnosticRow,
            in column: TechnicalDetailsColumn
        ) -> some View {
            let target = technicalDetailsTarget(for: row, in: column)

            return HStack(spacing: 0) {
                if let label = row.label {
                    Text(label)
                        .foregroundStyle(.secondary)

                    // swiftlint:disable:next hard_coded_display_string
                    Text(":")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)

                    Spacer(minLength: 8)

                    Text(row.value)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(row.value)
                        .foregroundStyle(row.isSecondary ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                Rectangle()
                    .fill(focusedTechnicalDetailsTarget == target ? Color.white.opacity(0.15) : .clear)
            }
            .contentShape(Rectangle())
            .focusable()
            .focused($focusedTechnicalDetailsTarget, equals: target)
            .onMoveCommand { direction in
                moveTechnicalDetailsFocus(from: target, direction: direction)
            }
        }

        private func diagnosticColumn(_ column: TechnicalDetailsColumn) -> some View {
            let columnIndex = column == .primary ? 0 : 1

            return VStack(alignment: .leading, spacing: 20) {
                ForEach(tvOSTechnicalDetailsColumns[columnIndex]) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 4)

                        ForEach(group.rows) { row in
                            diagnosticRow(row, in: column)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        #endif

        @ViewBuilder
        private var playbackInfoSection: some View {
            Text(L10n.mediaPlayback)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 4)

            LabeledContent(L10n.videoPlayer, value: Defaults[.VideoPlayer.videoPlayerType].displayTitle)

            if let playMethod = viewModel.currentSession?.playMethodDisplayTitle {
                LabeledContent(L10n.method, value: playMethod)
            }

            if let deliveryProtocol = mediaSource?.protocol {
                LabeledContent(L10n.source, value: deliveryProtocol.rawValue.uppercased())
            }

            if let transcodingSubProtocol = mediaSource?.transcodingSubProtocol {
                LabeledContent(L10n.protocol, value: transcodingSubProtocol.rawValue.uppercased())
            }
        }

        @ViewBuilder
        private var videoInfoSection: some View {
            if videoStream != nil || (manager.proxy as? any VideoMediaPlayerProxy) != nil {
                Text(L10n.video)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let width = videoStream?.width, let height = videoStream?.height {
                    LabeledContent(L10n.videoResolution, value: height.description.multiply(by: width.description))
                }

                if let proxy = manager.proxy as? any VideoMediaPlayerProxy {
                    LabeledContent(L10n.droppedFrames, value: proxy.droppedFrames.value.description)
                    LabeledContent(L10n.corruptedFrames, value: proxy.corruptedFrames.value.description)
                }
            }
        }

        @ViewBuilder
        private var streamingInfoSection: some View {
            if let transcodingInfo = viewModel.currentSession?.transcodingInfo {
                Text(viewModel.currentSession?.playMethodDisplayTitle.map { L10n.streamInfoWithMethod($0) } ?? L10n.streamInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let videoCodec = transcodingInfo.videoCodec {
                    LabeledContent(
                        L10n.videoCodec,
                        value: transcodingInfo.isVideoDirect == true
                            ? "\(videoCodec.uppercased()) (\(L10n.direct))"
                            : videoCodec.uppercased()
                    )
                }

                if let audioCodec = transcodingInfo.audioCodec {
                    LabeledContent(
                        L10n.audioCodec,
                        value: transcodingInfo.isAudioDirect == true
                            ? "\(audioCodec.uppercased()) (\(L10n.direct))"
                            : audioCodec.uppercased()
                    )
                }

                if let hwAccel = transcodingInfo.hardwareAccelerationType {
                    LabeledContent(L10n.hardwareAcceleration, value: hwAccel.rawValue)
                }

                if let completion = transcodingInfo.completionPercentage {
                    LabeledContent(L10n.transcodeProgress, value: "\(Int(completion))%")
                }
            }
        }

        @ViewBuilder
        private var originalMediaInfoSection: some View {
            if mediaSource != nil || videoStream != nil || audioStream != nil {
                Text(L10n.originalMediaInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let container = mediaSource?.container {
                    LabeledContent(L10n.container, value: container)
                }

                if let size = mediaSource?.size {
                    LabeledContent(L10n.size, value: Int64(size).formatted(.byteCount(style: .file)))
                }

                if let bitrate = mediaSource?.bitrate {
                    LabeledContent(L10n.bitrate, value: bitrate.formatted(.bitRate))
                }

                if let codec = videoStream?.codec {
                    let display = videoStream?.profile.map { "\(codec.uppercased()) \($0)" } ?? codec.uppercased()
                    LabeledContent(L10n.videoCodec, value: display)
                }

                if let bitRate = videoStream?.bitRate {
                    LabeledContent(L10n.videoBitRate, value: bitRate.formatted(.bitRate))
                }

                if let videoRangeType = videoStream?.videoRangeType {
                    LabeledContent(L10n.videoRangeType, value: videoRangeType.rawValue)
                }

                if let codec = audioStream?.codec {
                    LabeledContent(L10n.audioCodec, value: codec.uppercased())
                }

                if let bitRate = audioStream?.bitRate {
                    LabeledContent(L10n.audioBitrate, value: bitRate.formatted(.bitRate))
                }

                if let channels = audioStream?.channels {
                    LabeledContent(L10n.channels, value: "\(channels)")
                }

                if let sampleRate = audioStream?.sampleRate {
                    LabeledContent(L10n.audioSampleRate, value: "\(sampleRate) Hz")
                }
            }
        }

        @ViewBuilder
        private var transcodeReasonsSection: some View {
            if let transcodeReasons = viewModel.currentSession?.transcodingInfo?.transcodeReasons, transcodeReasons.isNotEmpty {
                Text(L10n.transcodeReasons)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                ForEach(transcodeReasons, id: \.self) { reason in
                    Text(reason.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        var iOSView: some View {
            CompactOrRegularView(
                isCompact: containerState.isCompact
            ) {
                compactView
            } regularView: {
                regularView
            }
            .labeledContentStyle(.playbackInfo)
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
        }

        @ViewBuilder
        private var compactView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    playbackInfoSection
                    videoInfoSection
                    originalMediaInfoSection
                    streamingInfoSection
                    transcodeReasonsSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        @ViewBuilder
        private var regularView: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        playbackInfoSection
                        videoInfoSection
                        streamingInfoSection
                        transcodeReasonsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 4) {
                        originalMediaInfoSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        var tvOSView: some View {
            #if os(tvOS)
            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    diagnosticColumn(.primary)
                    diagnosticColumn(.secondary)
                }
            }
            .scrollIndicators(.hidden)
            .edgePadding()
            .focusSection()
            .onChange(of: focusedTechnicalDetailsTarget) { _, target in
                containerState.isTechnicalDetailsContentFocused = target != nil
            }
            .onChange(of: containerState.playbackDropdownFocusRequest) { _, request in
                switch request {
                case .technicalDetailsFirstRow:
                    guard let firstRow = rows(in: .primary).first else { return }
                    focusedTechnicalDetailsTarget = technicalDetailsTarget(for: firstRow, in: .primary)
                    containerState.isTechnicalDetailsContentFocused = true

                case .section:
                    focusedTechnicalDetailsTarget = nil
                    containerState.isTechnicalDetailsContentFocused = false

                default:
                    break
                }
            }
            #else
            EmptyView()
            #endif
        }
    }
}

class PlaybackInformationProvider: ViewModel, MediaPlayerObserver {

    @Published
    var currentSession: SessionInfoDto? = nil

    weak var manager: MediaPlayerManager?

    init(itemID: String) {
        super.init()

        Container.shared.userSessionManager()
            .$currentSession
            .map { session -> AnyPublisher<[SessionInfoDto], Never> in
                session?.serverSocketManager.sessions() ?? Combine.Empty<[SessionInfoDto], Never>().eraseToAnyPublisher()
            }
            .switchToLatest()
            .sink { [weak self] sessions in
                Task { @MainActor in
                    guard let self else { return }

                    let deviceID = self.userSession?.client.configuration.deviceID
                    let deviceSessions = sessions.filter { $0.deviceID == deviceID }

                    self.currentSession = deviceSessions.first(where: { $0.nowPlayingItem?.id == itemID }) ?? deviceSessions.first
                }
            }
            .store(in: &cancellables)
    }
}
