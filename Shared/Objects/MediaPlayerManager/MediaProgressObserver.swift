//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI

// TODO: respond properly to end of playback
//       - when item changes
// TODO: only send stop on manager stop, not per-item

class MediaProgressObserver: ViewModel, MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let timer = PokeIntervalTimer()
    private var hasSentStart = false
    private var item: MediaPlayerItem?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing

    init(item: MediaPlayerItem) {
        self.item = item
        super.init()
    }

    private func sendReport() {
        guard let item else { return }

        switch lastPlaybackRequestStatus {
        case .playing:
            if hasSentStart {
                sendProgressReport(for: item, seconds: manager?.seconds)
            } else {
                sendStartReport(for: item, seconds: manager?.seconds)
            }
        case .paused:
            sendProgressReport(for: item, seconds: manager?.seconds, isPaused: true)
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        timer.sink { [weak self] in
            self?.sendReport()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.actions
            .sink { [weak self] in self?.didReceive(action: $0) }
            .store(in: &cancellables)

        manager.$playbackItem
            .sink { [weak self] in self?.playbackItemDidChange($0) }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] in self?.playbackRequestStatusDidChange($0) }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self] _ in self?.endPlaybackSession() }
            .store(in: &cancellables)
    }

    private func endPlaybackSession(seconds: Duration? = nil, ordinaryExit: Bool = false) {
        guard let item else { return }
        sendStopReport(for: item, seconds: seconds ?? manager?.seconds, ordinaryExit: ordinaryExit)
    }

    private func playbackItemDidChange(_ newItem: MediaPlayerItem?) {
        timer.poke()

        if let item, newItem !== item {
            endPlaybackSession(seconds: manager?.previousItemStopSeconds)
            self.item = newItem
            self.hasSentStart = false
            sendReport()
        }
    }

    private func playbackRequestStatusDidChange(_ newStatus: MediaPlayerManager.PlaybackRequestStatus) {
        timer.poke()
        lastPlaybackRequestStatus = newStatus
    }

    // TODO: respond to error
    // TODO: respond properly to ended
    private func didReceive(action: MediaPlayerManager._Action) {
        switch action {
        case .stop:
            #if DEBUG
            let position = manager.map { String($0.seconds.ticks) } ?? "nil"
            let runtime = item?.baseItem.runTimeTicks.map(String.init) ?? "nil"
            let played = manager?.item.userData?.isPlayed.map(String.init) ?? "nil"
            let itemPlayed = item?.baseItem.userData?.isPlayed.map(String.init) ?? "nil"
            print(
                "[WatchedTrace] ordinaryExit itemID=\(item?.baseItem.id ?? "nil") actualPosition=\(position) runtime=\(runtime) managerPresent=\(manager != nil)"
            )
            print(
                "[WatchedTrace] ordinaryExit before itemID=\(item?.baseItem.id ?? "nil") played=\(played) playbackItemPlayed=\(itemPlayed)"
            )
            #endif
            endPlaybackSession(ordinaryExit: true)
            timer.stop()
            cancellables = []
            item = nil
        default: ()
        }
    }

    private func sendStartReport(for item: MediaPlayerItem, seconds: Duration?) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        Task {
            var info = PlaybackStateInfo()
            info.audioStreamIndex = item.selectedAudioStreamIndex
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID
            info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

            let request = Paths.reportPlaybackStart(info)
            try await send(request)

            self.hasSentStart = true
        }
    }

    private func sendStopReport(for item: MediaPlayerItem, seconds: Duration?, ordinaryExit: Bool = false) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        Task {
            var info = PlaybackStopInfo()
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID

            let request = Paths.reportPlaybackStopped(info)
            #if DEBUG
            let ticks = seconds.map { String($0.ticks) } ?? "nil"
            print(
                "[WatchedTrace] transition=ordinaryStop itemID=\(item.baseItem.id ?? "nil") actualPosition=\(ticks) reportedPosition=\(ticks)"
            )
            #endif
            #if DEBUG && os(tvOS)
            if ordinaryExit {
                print(
                    "[WatchedTrace] ordinaryExit stopReport itemID=\(item.baseItem.id ?? "nil") endpoint=POST/Sessions/Playing/Stopped position=\(ticks) playedField=absent syntheticRuntime=false"
                )
                await debugReadExitState(itemID: item.baseItem.id, phase: "serverBefore")
            }
            #endif
            do {
                try await send(request)
                #if DEBUG && os(tvOS)
                if ordinaryExit {
                    print("[WatchedTrace] ordinaryExit stopReportAccepted itemID=\(item.baseItem.id ?? "nil")")
                    await debugReadExitState(itemID: item.baseItem.id, phase: "serverAfter")
                }
                #endif
            } catch {
                #if DEBUG
                if ordinaryExit {
                    print("[WatchedTrace] ordinaryExit stopReportFailed itemID=\(item.baseItem.id ?? "nil")")
                }
                #endif
                throw error
            }
        }
    }

    #if DEBUG && os(tvOS)
    private func debugReadExitState(itemID: String?, phase: String) async {
        guard let itemID else { return }
        do {
            let request = try Paths.getItem(itemID: itemID, userID: authenticatedUser.id)
            let response = try await send(request)
            let decoded = response.value
            let played = decoded.userData?.isPlayed.map(String.init) ?? "nil"
            let position = decoded.userData?.playbackPositionTicks.map(String.init) ?? "nil"
            let runtime = decoded.runTimeTicks.map(String.init) ?? "nil"
            let percentage = decoded.userData?.playedPercentage.map(String.init(describing:)) ?? "nil"
            print(
                "[WatchedTrace] ordinaryExit \(phase) itemID=\(decoded.id ?? "nil") played=\(played) position=\(position) runtime=\(runtime) playedPercentage=\(percentage)"
            )
            if phase == "serverAfter" {
                let progress = decoded.progressPercentage.map(String.init(describing:)) ?? "nil"
                print(
                    "[WatchedTrace] ordinaryExit localAfter itemID=\(decoded.id ?? "nil") source=freshDecodedResponse isPlayed=\(played) isWatched=\(decoded.userData?.isPlayed == true) progress=\(progress) remaining=\(decoded.progressLabel ?? "nil")"
                )
            }
        } catch {
            print("[WatchedTrace] ordinaryExit \(phase) itemID=\(itemID) readFailed=true")
        }
    }
    #endif

    private func sendProgressReport(for item: MediaPlayerItem, seconds: Duration?, isPaused: Bool = false) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        Task {
            var info = PlaybackStateInfo()
            info.audioStreamIndex = item.selectedAudioStreamIndex
            info.isPaused = isPaused
            info.itemID = item.baseItem.id
            info.liveStreamID = item.mediaSource.liveStreamID
            info.mediaSourceID = item.mediaSource.id
            info.playSessionID = item.playSessionID
            info.positionTicks = seconds?.ticks
            info.sessionID = item.playSessionID
            info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

            let request = Paths.reportPlaybackProgress(info)
            #if DEBUG
            let ticks = seconds.map { String($0.ticks) } ?? "nil"
            print(
                "[WatchedTrace] progressReport itemID=\(item.baseItem.id ?? "nil") endpoint=POST/Sessions/Playing/Progress position=\(ticks) playedField=absent syntheticRuntime=false"
            )
            #endif
            try await send(request)
        }
    }
}
