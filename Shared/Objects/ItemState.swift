//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI

@MainActor
final class ItemState: ObservableObject, Identifiable {

    let id: String

    @Published
    private(set) var userData: UserItemDataDto?

    private(set) var revision: UInt64

    init(itemID: String, userData: UserItemDataDto?, revision: UInt64 = 0) {
        self.id = itemID
        self.userData = userData
        self.revision = revision
    }

    func mergeSnapshot(_ incoming: UserItemDataDto?) {
        guard let incoming else { return }
        merge(incoming)
    }

    func apply(_ update: ItemUpdate) {
        guard update.itemID == id, update.revision > revision else { return }
        revision = update.revision

        switch update.change {
        case let .userData(incoming):
            merge(incoming)
        case let .playbackPositionTicks(ticks):
            updatePlaybackPosition(ticks)
        case let .playbackStopped(positionTicks):
            if let positionTicks {
                updatePlaybackPosition(positionTicks)
            }
        }
    }

    func applying(to item: BaseItemDto) -> BaseItemDto {
        guard item.id == id else { return item }
        var updated = item
        if let userData {
            updated.userData = userData
        }
        return updated
    }

    private func merge(_ incoming: UserItemDataDto) {
        var merged = userData ?? UserItemDataDto(itemID: id, key: incoming.key)

        if let isFavorite = incoming.isFavorite {
            merged.isFavorite = isFavorite
        }
        if let isLikes = incoming.isLikes {
            merged.isLikes = isLikes
        }
        if let isPlayed = incoming.isPlayed {
            merged.isPlayed = isPlayed
        }
        if let lastPlayedDate = incoming.lastPlayedDate {
            merged.lastPlayedDate = lastPlayedDate
        }
        if let playCount = incoming.playCount {
            merged.playCount = playCount
        }
        if let playbackPositionTicks = incoming.playbackPositionTicks {
            merged.playbackPositionTicks = playbackPositionTicks
        }
        if let playedPercentage = incoming.playedPercentage {
            merged.playedPercentage = playedPercentage
        }
        if let rating = incoming.rating {
            merged.rating = rating
        }
        if let unplayedItemCount = incoming.unplayedItemCount {
            merged.unplayedItemCount = unplayedItemCount
        }

        merged.itemID = id
        merged.key = incoming.key
        if merged != userData {
            userData = merged
        }
    }

    private func updatePlaybackPosition(_ ticks: Int) {
        var updated = userData ?? UserItemDataDto(itemID: id, key: id)
        updated.itemID = id
        updated.playbackPositionTicks = ticks
        if updated != userData {
            userData = updated
        }
    }
}

@MainActor
final class ItemStateStore {

    private final class WeakItemState {
        weak var value: ItemState?

        init(_ value: ItemState) {
            self.value = value
        }
    }

    let userSessionID: UUID

    private var states: [String: WeakItemState] = [:]
    private var latestUpdateByItem: [String: ItemUpdate] = [:]
    private var updateAccessOrder: [String] = []
    private var lookupCount = 0
    private var cancellables = Set<AnyCancellable>()

    private let maximumRememberedUpdates = 512

    init(userSessionID: UUID) {
        self.userSessionID = userSessionID

        Notifications[.itemUserDataDidChange]
            .publisher
            .filter { $0.userSessionID == userSessionID }
            .sink { [weak self] update in
                self?.apply(update)
            }
            .store(in: &cancellables)
    }

    func state(for item: BaseItemDto) -> ItemState? {
        guard let itemID = item.id else { return nil }
        pruneDeadStatesPeriodically()

        if let state = states[itemID]?.value {
            return state
        }

        let state = ItemState(
            itemID: itemID,
            userData: item.userData,
            revision: 0
        )
        states[itemID] = WeakItemState(state)
        if let update = latestUpdateByItem[itemID] {
            state.apply(update)
        }
        return state
    }

    private func apply(_ update: ItemUpdate) {
        guard update.userSessionID == userSessionID else { return }
        let currentRevision = max(
            latestUpdateByItem[update.itemID]?.revision ?? 0,
            states[update.itemID]?.value?.revision ?? 0
        )
        guard update.revision > currentRevision else { return }
        remember(update)
        pruneDeadStatesPeriodically()
        states[update.itemID]?.value?.apply(update)
    }

    func reset() {
        cancellables.removeAll()
        states.removeAll()
        latestUpdateByItem.removeAll()
        updateAccessOrder.removeAll()
    }

    private func remember(_ update: ItemUpdate) {
        latestUpdateByItem[update.itemID] = update
        updateAccessOrder.removeAll { $0 == update.itemID }
        updateAccessOrder.append(update.itemID)

        while updateAccessOrder.count > maximumRememberedUpdates {
            let evictedItemID = updateAccessOrder.removeFirst()
            latestUpdateByItem[evictedItemID] = nil
        }
    }

    private func pruneDeadStatesPeriodically() {
        lookupCount &+= 1
        guard lookupCount.isMultiple(of: 64) else { return }
        states = states.filter { $0.value.value != nil }
    }
}

extension UserItemDataDto {

    func mergingNonNilFields(from incoming: UserItemDataDto, itemID: String) -> Self {
        var merged = self
        if let isFavorite = incoming.isFavorite {
            merged.isFavorite = isFavorite
        }
        if let isLikes = incoming.isLikes {
            merged.isLikes = isLikes
        }
        if let isPlayed = incoming.isPlayed {
            merged.isPlayed = isPlayed
        }
        if let lastPlayedDate = incoming.lastPlayedDate {
            merged.lastPlayedDate = lastPlayedDate
        }
        if let playCount = incoming.playCount {
            merged.playCount = playCount
        }
        if let playbackPositionTicks = incoming.playbackPositionTicks {
            merged.playbackPositionTicks = playbackPositionTicks
        }
        if let playedPercentage = incoming.playedPercentage {
            merged.playedPercentage = playedPercentage
        }
        if let rating = incoming.rating {
            merged.rating = rating
        }
        if let unplayedItemCount = incoming.unplayedItemCount {
            merged.unplayedItemCount = unplayedItemCount
        }
        merged.itemID = itemID
        merged.key = incoming.key
        return merged
    }
}
