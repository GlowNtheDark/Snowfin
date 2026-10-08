//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import UIKit

extension Container {
    var notificationCenter: Factory<NotificationCenter> {
        self { NotificationCenter.default }.singleton
    }
}

enum Notifications {

    typealias Keys = _AnyKey

    class _AnyKey {
        typealias Key = Notifications.Key
    }

    class Key<Payload>: _AnyKey {

        @Injected(\.notificationCenter)
        private var notificationCenter

        let name: Notification.Name
        let decodeStrategy: ([AnyHashable: Any]) -> Payload?

        static func defaultDecodeStrategy(userInfo: [AnyHashable: Any]) -> Payload? {
            if let payload = userInfo["payload"] as? Payload {
                return payload
            }
            return nil
        }

        var rawValue: String {
            name.rawValue
        }

        convenience init(_ string: String) {
            self.init(Notification.Name(string))
        }

        init(
            _ name: Notification.Name,
            decodeStrategy: (([AnyHashable: Any]) -> Payload?)? = nil
        ) {
            self.name = name
            self.decodeStrategy = decodeStrategy ?? Self.defaultDecodeStrategy
        }

        func post(_ payload: Payload) {
            notificationCenter
                .post(
                    name: name,
                    object: nil,
                    userInfo: ["payload": payload]
                )
        }

        func post() where Payload == Void {
            notificationCenter
                .post(
                    name: name,
                    object: nil,
                    userInfo: nil
                )
        }

        var publisher: AnyPublisher<Payload, Never> {
            notificationCenter
                .publisher(for: name)
                .compactMap { output in
                    if Payload.self == Void.self {
                        return () as? Payload
                    }

                    guard let userInfo = output.userInfo else {
                        return nil
                    }

                    return self.decodeStrategy(userInfo)
                }
                .eraseToAnyPublisher()
        }
    }

    static subscript<Payload>(key: Key<Payload>) -> Key<Payload> {
        key
    }
}

/// An accepted item update tied to the session that issued the request.
/// `revision` is captured before the request starts so a slower older reply
/// cannot replace a newer accepted update.
struct ItemUpdate: Sendable {

    enum Change: Sendable {
        case userData(UserItemDataDto)
        case playbackPositionTicks(Int)
        case playbackStopped(positionTicks: Int?)
    }

    let userSessionID: UUID
    let itemID: String
    let revision: UInt64
    let change: Change

    var userDataPatch: UserItemDataDto? {
        switch change {
        case let .userData(userData):
            userData
        case let .playbackPositionTicks(ticks):
            UserItemDataDto(itemID: itemID, key: itemID, playbackPositionTicks: ticks)
        case let .playbackStopped(positionTicks):
            positionTicks.map {
                UserItemDataDto(itemID: itemID, key: itemID, playbackPositionTicks: $0)
            }
        }
    }
}

/// Requests an authoritative refresh of already-loaded episode user data after
/// a series-level play-state mutation.
struct SeriesDescendantUserDataReconciliation: Sendable {
    let userSessionID: UUID
    let seriesID: String
}

// MARK: - Keys

extension Notifications.Key {

    // MARK: - App Flow

    static var didPurge: Key<Void> {
        Key("didPurge")
    }

    static var didChangeServerConnection: Key<ServerConnection> {
        Key("didChangeServerConnection")
    }

    static var didSendStopReport: Key<String> {
        Key("didSendStopReport")
    }

    #if os(tvOS)
    static var didSendResumeProgressReport: Key<Void> {
        Key("didSendResumeProgressReport")
    }
    #endif

    static var didRequestGlobalRefresh: Key<Void> {
        Key("didRequestGlobalRefresh")
    }

    // MARK: - Media Items

    // TODO: come up with a cleaner, more defined way for item update notifications

    static var itemUserDataDidChange: Key<ItemUpdate> {
        Key("itemUserDataDidChange")
    }

    static var seriesDescendantUserDataNeedsReconciliation: Key<SeriesDescendantUserDataReconciliation> {
        Key("seriesDescendantUserDataNeedsReconciliation")
    }

    /// - Payload: The new item with updated metadata.
    static var itemMetadataDidChange: Key<BaseItemDto> {
        Key("itemMetadataDidChange")
    }

    /// - Payload: The ID of the deleted item.
    static var didDeleteItem: Key<String> {
        Key("didDeleteItem")
    }

    // MARK: - Server

    static var didConnectToServer: Key<ServerState> {
        Key("didConnectToServer")
    }

    static var didDeleteServer: Key<ServerState> {
        Key("didDeleteServer")
    }

    // MARK: - User

    /// - Payload: The ID of the user whose Profile Image changed.
    static var didChangeUserProfile: Key<String> {
        Key("didChangeUserProfile")
    }

    static var didAddServerUser: Key<UserDto> {
        Key("didAddServerUser")
    }

    // MARK: - Playback

    static var didStartPlayback: Key<Void> {
        Key("didStartPlayback")
    }

    static var interruption: Key<Void> {
        Key(AVAudioSession.interruptionNotification)
    }

    // MARK: - UIApplication

    static var applicationDidEnterBackground: Key<Void> {
        Key(UIApplication.didEnterBackgroundNotification)
    }

    static var applicationWillEnterForeground: Key<Void> {
        Key(UIApplication.willEnterForegroundNotification)
    }

    static var applicationWillResignActive: Key<Void> {
        Key(UIApplication.willResignActiveNotification)
    }

    static var applicationWillTerminate: Key<Void> {
        Key(UIApplication.willTerminateNotification)
    }

    static var sceneDidEnterBackground: Key<Void> {
        Key(UIScene.didEnterBackgroundNotification)
    }

    static var sceneWillEnterForeground: Key<Void> {
        Key(UIScene.willEnterForegroundNotification)
    }

    static var avAudioSessionInterruption: Key<(AVAudioSession.InterruptionType, AVAudioSession.InterruptionOptions)> {
        Key(AVAudioSession.interruptionNotification) { userInfo in
            guard let rawValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue)
            else {
                return nil
            }
            let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []

            return (type, options)
        }
    }
}
