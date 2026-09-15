//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
#if os(tvOS)
import JellyfinAPI
#endif

@MainActor
final class FocusCoordinator: ObservableObject {

    @Published
    private(set) var focusedIDs: Set<String> = []
    @Published
    private(set) var lastFocusedIDs: Set<String> = []
    @Published
    private(set) var request: String?

    #if os(tvOS)
    struct HomeTile: Equatable {
        let groupID: String
        let itemID: String
        let seriesID: String?
        let index: Int

        // Length-prefix the group so the pair cannot collide at a separator.
        var target: String {
            "home:\(groupID.utf8.count):\(groupID):\(itemID)"
        }
    }

    @Published
    private(set) var protectsHomeReturn = false
    @Published
    private(set) var homeRevision = 0
    @Published
    private(set) var homeReturnTarget: HomeTile?
    @Published
    private(set) var defersHomeRefresh = false
    private var homeOrigin: HomeTile?
    private var selectedHomeTile: HomeTile?
    private var playerPresentationActive = false
    private var restoresAfterDetailsDismissal = false
    private var waitingForHomeRefresh = false
    private var refreshedHome = false
    private var preparedHomeReturn = false
    private var rowScrollers: [String: (Int) -> Bool] = [:]
    private var revealedTarget: String?
    private var readyHomeTarget: String?

    func selectHomeTile(_ tile: HomeTile) {
        selectedHomeTile = tile
        guard tile.groupID == CinematicSelectionContentGroup.homeGroupID else { return }
        beginHomeReturn(origin: tile, playerPresentationActive: false, fromDetails: true)
    }

    /// Starts a Home return only after the player presentation identifies its
    /// actual parent, distinguishing direct Home playback from playback nested
    /// over Details.
    func homePlayerPresented(fromDetails: Bool) {
        guard let selectedHomeTile else { return }
        beginHomeReturn(origin: selectedHomeTile, playerPresentationActive: true, fromDetails: fromDetails)
    }

    private func beginHomeReturn(origin: HomeTile, playerPresentationActive: Bool, fromDetails: Bool) {
        homeOrigin = origin
        protectsHomeReturn = true
        self.playerPresentationActive = playerPresentationActive
        restoresAfterDetailsDismissal = fromDetails
        defersHomeRefresh = fromDetails
        waitingForHomeRefresh = false
        refreshedHome = false
        preparedHomeReturn = false
        homeReturnTarget = nil
        revealedTarget = nil
        readyHomeTarget = nil
    }

    func homePlayerDismissed() {
        guard protectsHomeReturn else { return }
        playerPresentationActive = false

        // Settle refreshed rows while Details still covers Home, but keep the
        // actual focus request dormant until Details itself is dismissed.
        if restoresAfterDetailsDismissal {
            waitingForHomeRefresh = true
            defersHomeRefresh = false
            return
        }

        if refreshedHome {
            prepareHomeReturn()
        } else {
            waitingForHomeRefresh = true
        }
    }

    /// A Details-origin player must leave the Home focus target dormant until
    /// its parent Details presentation is explicitly dismissed.
    func homeDetailsDismissed() {
        guard protectsHomeReturn, restoresAfterDetailsDismissal, !playerPresentationActive else { return }
        restoresAfterDetailsDismissal = false
        defersHomeRefresh = false

        if !refreshedHome {
            // Opening and dismissing Details without playback has no refresh
            // event to wait for. Resolve against the already-settled Home rows.
            guard !waitingForHomeRefresh else { return }
            refreshedHome = true
        }

        prepareHomeReturn()
        requestHomeFocusIfReady()
    }

    func homeStopReported() {
        guard protectsHomeReturn, !restoresAfterDetailsDismissal else { return }
        waitingForHomeRefresh = true
    }

    func homeRefreshFinished() {
        guard waitingForHomeRefresh else { return }
        waitingForHomeRefresh = false
        refreshedHome = true

        guard !playerPresentationActive else { return }
        prepareHomeReturn()
    }

    private func prepareHomeReturn() {
        guard !preparedHomeReturn else { return }
        preparedHomeReturn = true
        homeReturnTarget = nil
        readyHomeTarget = nil
        // A new preference pass supplies the refreshed, complete row manifests.
        homeRevision += 1
    }

    func resolveHomeReturn(rows: [HomeFocusRow]) {
        guard refreshedHome, protectsHomeReturn, homeReturnTarget == nil,
              let origin = homeOrigin, !rows.isEmpty,
              rows.allSatisfy({ $0.revision == homeRevision })
        else { return }

        let ordered = rows.sorted { $0.order < $1.order }
        let originalRow = ordered.first { $0.groupID == origin.groupID }?.tiles ?? []
        let exact = originalRow.first { $0.itemID == origin.itemID }
        let replacement: HomeTile? = if origin.groupID == CinematicSelectionContentGroup.homeGroupID {
            originalRow.first {
                origin.seriesID?.isEmpty == false && $0.seriesID == origin.seriesID
            }
        } else {
            nil
        }
        let nearest = originalRow.min {
            let lhs = abs($0.index - origin.index)
            let rhs = abs($1.index - origin.index)
            return lhs == rhs ? $0.index < $1.index : lhs < rhs
        }
        homeReturnTarget = exact ?? replacement ?? nearest ?? ordered.flatMap(\.tiles).first
        if homeReturnTarget == nil {
            cancelHomeReturn()
        } else {
            revealHomeTile()
        }
    }

    // CollectionHStack virtualizes its cells. Reveal the resolved index before
    // waiting for that tile's normal UIKit/SwiftUI readiness callback.
    func registerHomeRowScroller(groupID: String, from view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let collection = current as? UICollectionView {
                rowScrollers[groupID] = { [weak collection] index in
                    guard let collection, collection.numberOfSections > 0,
                          index < collection.numberOfItems(inSection: 0) else { return false }
                    collection.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
                    return true
                }
                revealHomeTile()
                return
            }
            ancestor = current.superview
        }
    }

    private func revealHomeTile() {
        guard let tile = homeReturnTarget, revealedTarget != tile.target,
              let scroll = rowScrollers[tile.groupID] else { return }
        revealedTarget = tile.target
        if !scroll(tile.index) {
            revealedTarget = nil
        }
    }

    func homeTileReady(_ tile: HomeTile) {
        guard protectsHomeReturn, homeReturnTarget?.target == tile.target else { return }
        readyHomeTarget = tile.target
        requestHomeFocusIfReady()
    }

    private func requestHomeFocusIfReady() {
        guard protectsHomeReturn, !playerPresentationActive, !restoresAfterDetailsDismissal,
              let target = homeReturnTarget?.target, readyHomeTarget == target
        else { return }
        focus(target)
    }

    func homeTileAcquired(_ tile: HomeTile) {
        guard homeReturnTarget?.target == tile.target else { return }
        cancelHomeReturn()
        clearRequest()
    }

    func cancelHomeReturn() {
        protectsHomeReturn = false
        homeOrigin = nil
        selectedHomeTile = nil
        playerPresentationActive = false
        restoresAfterDetailsDismissal = false
        waitingForHomeRefresh = false
        refreshedHome = false
        preparedHomeReturn = false
        homeReturnTarget = nil
        revealedTarget = nil
        readyHomeTarget = nil
        defersHomeRefresh = false
    }
    #endif

    init(initial: String? = nil) {
        self.request = initial
    }

    func focus(_ id: String) {
        request = id
    }

    func clearRequest() {
        request = nil
    }

    fileprivate func update(_ id: String, isFocused: Bool) {
        if isFocused {
            focusedIDs.insert(id)
        } else {
            focusedIDs.remove(id)
        }

        if focusedIDs.isNotEmpty {
            lastFocusedIDs = focusedIDs
        }
    }
}

#if os(tvOS)
struct HomeFocusRow: Equatable {
    let groupID: String
    let order: Int
    let revision: Int
    let tiles: [FocusCoordinator.HomeTile]
}

struct HomeFocusRowsKey: PreferenceKey {
    static var defaultValue: [HomeFocusRow] {
        []
    }

    static func reduce(value: inout [HomeFocusRow], nextValue: () -> [HomeFocusRow]) {
        value.append(contentsOf: nextValue())
    }
}

extension EnvironmentValues {
    @Entry
    var homeTileCoordinator: FocusCoordinator? = nil
    @Entry
    var homeFocusGroup: String? = nil
    @Entry
    var homeFocusRowOrder = 0
    @Entry
    var homeFocusRevision = 0
    @Entry
    var homeFocusTile: FocusCoordinator.HomeTile? = nil
    @Entry
    var registerHomeFocus: ((FocusCoordinator, NavigationCoordinator) -> Void)? = nil
}

extension FocusCoordinator.HomeTile {
    static func make(poster: any Poster, groupID: String, index: Int) -> Self? {
        if let wrapped = poster as? AnyPoster {
            return make(poster: wrapped._poster, groupID: groupID, index: index)
        }
        guard let item = poster as? BaseItemDto, let id = item.id, !id.isEmpty else { return nil }
        return .init(groupID: groupID, itemID: id, seriesID: item.seriesID, index: index)
    }
}
#endif

private struct CoordinatedFocusModifier: ViewModifier {

    @EnvironmentObject
    private var coordinator: FocusCoordinator

    @FocusState
    private var isFocused: Bool

    let id: String

    private func apply(_ request: String?) {
        guard let request else { return }

        if request == id {
            isFocused = true
        }
    }

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear {
                apply(coordinator.request)
                coordinator.update(id, isFocused: isFocused)
            }
            .onChange(of: isFocused) {
                coordinator.update(id, isFocused: isFocused)
            }
        #if os(tvOS)
            .onReceive(coordinator.$request) { request in
                apply(request)
            }
        #else
            .onChange(of: coordinator.request) {
                apply(coordinator.request)
            }
        #endif
            .onDisappear {
                    coordinator.update(id, isFocused: false)
                }
    }
}

private struct CoordinatedFocusSelectionModifier: ViewModifier {

    @EnvironmentObject
    private var coordinator: FocusCoordinator

    let id: String
    let selection: FocusState<String?>.Binding

    private func apply(_ request: String?) {
        guard let request else { return }

        if request == id {
            selection.wrappedValue = id
        }
    }

    func body(content: Content) -> some View {
        content
            .focused(selection, equals: id)
            .onAppear {
                apply(coordinator.request)
                coordinator.update(id, isFocused: selection.wrappedValue == id)
            }
            .onChange(of: selection.wrappedValue) {
                coordinator.update(id, isFocused: selection.wrappedValue == id)
            }
        #if os(tvOS)
            .onReceive(coordinator.$request) { request in
                apply(request)
            }
        #else
            .onChange(of: coordinator.request) {
                apply(coordinator.request)
            }
        #endif
            .onDisappear {
                    coordinator.update(id, isFocused: false)
                }
    }
}

extension View {

    func coordinatedFocus(_ id: String) -> some View {
        modifier(CoordinatedFocusModifier(id: id))
    }

    func coordinatedFocus(
        _ id: String,
        selection: FocusState<String?>.Binding
    ) -> some View {
        modifier(CoordinatedFocusSelectionModifier(id: id, selection: selection))
    }
}
