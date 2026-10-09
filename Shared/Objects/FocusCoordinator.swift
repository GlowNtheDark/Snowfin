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
    private var homeFocusRows: [HomeFocusRow] = []
    private var homeTileProbes: [String: WeakHomeFocusProbe] = [:]
    private var focusedHomeTile: HomeTile?
    private var pendingHomeVerticalTarget: String?
    private var lastHomeVerticalTransition: HomeVerticalTransition?
    private var homeVerticalScrollSuppressions: Set<String> = []
    private var homeVerticalRecognizer: HomeVerticalTransitionRecognizer?

    func updateHomeFocusRows(_ rows: [HomeFocusRow]) {
        if homeFocusRows.map(\.membershipSignature) != rows.map(\.membershipSignature) {
            lastHomeVerticalTransition = nil
        }
        homeFocusRows = rows
    }

    func registerHomeFocusTile(_ tile: HomeTile, from view: UIView) {
        guard let probe = view as? LaunchFocusCandidateProbe.ProbeView else { return }
        homeTileProbes[tile.target] = WeakHomeFocusProbe(tile: tile, view: probe)

        guard let scrollView = homeVerticalScrollView(ancestorOf: probe) else { return }
        if homeVerticalRecognizer?.view !== scrollView {
            if let homeVerticalRecognizer, let oldView = homeVerticalRecognizer.view {
                oldView.removeGestureRecognizer(homeVerticalRecognizer)
            }
            let recognizer = HomeVerticalTransitionRecognizer(coordinator: self)
            scrollView.addGestureRecognizer(recognizer)
            homeVerticalRecognizer = recognizer
        }
    }

    func recordHomeTileFocus(_ tile: HomeTile, isFocused: Bool) {
        if isFocused {
            if pendingHomeVerticalTarget == tile.target {
                pendingHomeVerticalTarget = nil
            } else if focusedHomeTile?.target != tile.target {
                lastHomeVerticalTransition = nil
            }
            focusedHomeTile = tile
        } else if focusedHomeTile?.target == tile.target {
            focusedHomeTile = nil
        }
    }

    func consumeHomeVerticalScrollSuppression(for tile: HomeTile) -> Bool {
        homeVerticalScrollSuppressions.remove(tile.target) != nil
    }

    fileprivate func homeVerticalPressDecision(
        _ presses: Set<UIPress>,
        in view: UIView?
    ) -> HomeVerticalPressDecision {
        guard let direction = HomeVerticalDirection(presses: presses),
              let source = focusedHomeTile,
              let window = (view as? UIWindow) ?? view?.window
        else { return .passThrough }

        let rows = homeFocusRows.filter { !$0.tiles.isEmpty }.sorted { $0.order < $1.order }
        guard let sourceRowIndex = rows.firstIndex(where: { $0.groupID == source.groupID }) else {
            lastHomeVerticalTransition = nil
            return .consume
        }

        let destinationIndex = sourceRowIndex + direction.rowDelta
        guard rows.indices.contains(destinationIndex) else { return .passThrough }

        guard let sourceRegistration = homeFocusCandidate(source, in: window) else {
            lastHomeVerticalTransition = nil
            return .consume
        }

        let sourceRow = rows[sourceRowIndex]
        let destinationRow = rows[destinationIndex]
        let destination: HomeTile?

        if let previous = lastHomeVerticalTransition,
           previous.destination.target == source.target,
           previous.direction == direction.opposite,
           previous.destinationGroupID == sourceRow.groupID,
           previous.sourceGroupID == destinationRow.groupID,
           previous.destinationMembership == sourceRow.membershipSignature,
           previous.sourceMembership == destinationRow.membershipSignature
        {
            // Exact immediate reversal takes precedence over the new geometry.
            guard let exactOrigin = destinationRow.tiles.first(where: { $0.target == previous.source.target }),
                  homeFocusCandidate(exactOrigin, in: window) != nil
            else {
                lastHomeVerticalTransition = nil
                return .consume
            }
            destination = exactOrigin
        } else {
            destination = destinationRow.tiles
                .compactMap { tile -> (HomeTile, CGRect)? in
                    guard let registration = homeFocusCandidate(tile, in: window) else { return nil }
                    return (tile, registration.frame)
                }
                .min { lhs, rhs in
                    let leftDistance = abs(lhs.1.midX - sourceRegistration.frame.midX)
                    let rightDistance = abs(rhs.1.midX - sourceRegistration.frame.midX)
                    return leftDistance == rightDistance ? lhs.0.index < rhs.0.index : leftDistance < rightDistance
                }?
                .0
        }

        guard let destination else {
            // Never hand a missing adjacent target back to spatial search; it could skip this shelf.
            lastHomeVerticalTransition = nil
            return .consume
        }

        let transition = HomeVerticalTransition(
            source: source,
            destination: destination,
            direction: direction,
            sourceGroupID: sourceRow.groupID,
            destinationGroupID: destinationRow.groupID,
            sourceMembership: sourceRow.membershipSignature,
            destinationMembership: destinationRow.membershipSignature
        )
        return .move(transition)
    }

    fileprivate func performHomeVerticalTransition(_ transition: HomeVerticalTransition) {
        guard focusedHomeTile?.target == transition.source.target,
              let window = homeTileProbes[transition.destination.target]?.view?.window,
              let registration = homeTileProbes[transition.destination.target],
              registration.view?.homeTile == transition.destination,
              homeFocusCandidate(transition.destination, in: window) != nil,
              let requestFocus = registration.view?.onRequestFocus
        else { return }

        lastHomeVerticalTransition = transition
        pendingHomeVerticalTarget = transition.destination.target
        homeVerticalScrollSuppressions.insert(transition.destination.target)
        requestFocus()
    }

    private func homeFocusCandidate(_ tile: HomeTile, in window: UIWindow) -> (view: LaunchFocusCandidateProbe.ProbeView, frame: CGRect)? {
        guard let probe = homeTileProbes[tile.target]?.view,
              probe.homeTile == tile,
              probe.window === window,
              !probe.bounds.isEmpty,
              let collection = homeCollectionView(ancestorOf: probe),
              collection.visibleCells.contains(where: { probe.isDescendant(of: $0) })
        else { return nil }

        var effectiveAlpha: CGFloat = 1
        var ancestor: UIView? = probe
        while let current = ancestor {
            guard !current.isHidden else { return nil }
            effectiveAlpha *= current.alpha
            ancestor = current.superview
        }
        guard effectiveAlpha > 0.99 else { return nil }

        let frame = probe.convert(probe.bounds, to: window)
        let visibleViewport = collection.convert(collection.bounds, to: window)
        guard frame.intersects(visibleViewport) else { return nil }
        return (probe, frame)
    }

    private func homeCollectionView(ancestorOf view: UIView) -> UICollectionView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let collection = current as? UICollectionView {
                return collection
            }
            ancestor = current.superview
        }
        return nil
    }

    private func homeVerticalScrollView(ancestorOf view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView, !(scrollView is UICollectionView) {
                return scrollView
            }
            ancestor = current.superview
        }
        return nil
    }

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
private final class WeakHomeFocusProbe {
    let tile: FocusCoordinator.HomeTile
    weak var view: LaunchFocusCandidateProbe.ProbeView?

    init(tile: FocusCoordinator.HomeTile, view: LaunchFocusCandidateProbe.ProbeView) {
        self.tile = tile
        self.view = view
    }
}

fileprivate enum HomeVerticalDirection: Equatable {
    case up
    case down

    var rowDelta: Int {
        self == .down ? 1 : -1
    }

    var opposite: Self {
        self == .down ? .up : .down
    }

    init?(presses: Set<UIPress>) {
        let directions = presses.compactMap { press -> Self? in
            switch press.type {
            case .upArrow: .up
            case .downArrow: .down
            default: nil
            }
        }
        guard directions.count == 1, let direction = directions.first else { return nil }
        self = direction
    }
}

fileprivate struct HomeVerticalTransition {
    let source: FocusCoordinator.HomeTile
    let destination: FocusCoordinator.HomeTile
    let direction: HomeVerticalDirection
    let sourceGroupID: String
    let destinationGroupID: String
    let sourceMembership: [String]
    let destinationMembership: [String]
}

fileprivate enum HomeVerticalPressDecision {
    case passThrough
    case consume
    case move(HomeVerticalTransition)
}

private final class HomeVerticalTransitionRecognizer: UIGestureRecognizer {
    weak var coordinator: FocusCoordinator?

    init(coordinator: FocusCoordinator) {
        self.coordinator = coordinator
        super.init(target: nil, action: nil)
        allowedPressTypes = [
            NSNumber(value: UIPress.PressType.upArrow.rawValue),
            NSNumber(value: UIPress.PressType.downArrow.rawValue),
        ]
        cancelsTouchesInView = true
        delaysTouchesBegan = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        switch coordinator?.homeVerticalPressDecision(presses, in: view) ?? .passThrough {
        case .passThrough:
            if let event {
                super.pressesBegan(presses, with: event)
            }
            state = .failed
        case .consume:
            state = .recognized
        case let .move(transition):
            // Claim this press before asking the registered SwiftUI tile to take focus.
            state = .recognized
            coordinator?.performHomeVerticalTransition(transition)
        }
    }
}

struct HomeFocusRow: Equatable {
    let groupID: String
    let order: Int
    let revision: Int
    let tiles: [FocusCoordinator.HomeTile]

    var membershipSignature: [String] {
        tiles.map(\.target)
    }
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
    let consumesRequestOnAcquisition: Bool

    private func consumeRequestIfNeeded() {
        guard consumesRequestOnAcquisition, coordinator.request == id else { return }
        coordinator.clearRequest()
    }

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
                if isFocused {
                    consumeRequestIfNeeded()
                }
            }
            .onChange(of: isFocused) {
                coordinator.update(id, isFocused: isFocused)
                if isFocused {
                    consumeRequestIfNeeded()
                }
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

    func coordinatedFocus(_ id: String, consumesRequestOnAcquisition: Bool = false) -> some View {
        modifier(CoordinatedFocusModifier(id: id, consumesRequestOnAcquisition: consumesRequestOnAcquisition))
    }

    func coordinatedFocus(
        _ id: String,
        selection: FocusState<String?>.Binding
    ) -> some View {
        modifier(CoordinatedFocusSelectionModifier(id: id, selection: selection))
    }
}
