//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct PagingLibraryView<Library: PagingLibrary>: View where Library.Element: LibraryElement {

    typealias Element = Library.Element

    @Default(.Customization.Library.rememberLayout)
    private var rememberIndividualLibraryStyle
    @Default(.Customization.Library.style)
    private var defaultLibraryStyle

    @Environment(\.isTabContentActive)
    private var tabContentActivity

    private var isTabContentActive: Bool {
        tabContentActivity
    }

    @Environment(\.scenePhase)
    private var scenePhase

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    @Namespace
    private var namespace

    @Router
    private var router

    @State
    private var isSafeAreaBarApplied: Bool = false

    @StateObject
    private var gridProxy = CollectionVGridProxy()
    #if os(tvOS)
    @StateObject
    private var gridScrollCoordinator = CollectionVGridScrollCoordinator()

    @FocusState
    private var focusedElementID: Element.ID?

    @FocusState
    private var isEmptyContentFocused: Bool

    @EnvironmentObject
    private var navigationCoordinator: NavigationCoordinator

    @EnvironmentObject
    private var tabContentFocusHandoff: TabContentFocusHandoff

    @Environment(\.isTabContentFocusable)
    private var isTabContentFocusable

    @Environment(\.episodeRouteTabID)
    private var episodeRouteTabID

    @State
    private var pendingEpisodeRouteOrigin: EpisodeRouteIntent.Origin?

    @State
    private var tabActivationRefreshTask: Task<Void, Never>?

    @State
    private var savedFocusedElementID: Element.ID?

    @State
    private var gridLocatorID = UUID()

    @State
    private var isLetterRestorePending: Bool = false
    #endif
    @StateObject
    private var viewModel: PagingLibraryViewModel<Library>

    private let observesItemState: Bool

    @StoredValue
    private var parentLibraryStyle: LibraryStyle

    @TabItemSelected
    private var tabItemSelected

    private var libraryStyleOptions: LibraryStyleOptions {
        viewModel.libraryStyleOptions
    }

    private var libraryStyle: LibraryStyle {
        libraryStyleOptions.normalized(storedLibraryStyle)
    }

    private var isLibraryStyleSectionVisible: Bool {
        libraryStyleOptions.hasVisibleControls ||
            (
                libraryStyle.displayType == .list &&
                    UIDevice.isPad &&
                    libraryStyleOptions.displayTypes.contains(.list)
            )
    }

    private var storedLibraryStyle: LibraryStyle {
        rememberIndividualLibraryStyle ? parentLibraryStyle : defaultLibraryStyle
    }

    private var storedLibraryStyleBinding: Binding<LibraryStyle> {
        rememberIndividualLibraryStyle ? $parentLibraryStyle : $defaultLibraryStyle
    }

    private var episodeRouteOriginContext: EpisodeRouteOriginContext? {
        guard let episodeRouteTabID else { return nil }
        return EpisodeRouteOriginContext(
            source: .library(tabID: episodeRouteTabID, libraryID: viewModel.id),
            focusCoordinator: nil,
            libraryIndexForItemID: { itemID in
                viewModel.displayedElements.firstIndex { element in
                    (element as? BaseItemDto)?.id == itemID
                }
            }
        )
    }

    init(
        library: Library,
        automaticallyRefreshes: Bool = false,
        observesItemState: Bool = false
    ) {
        self.observesItemState = observesItemState
        self._parentLibraryStyle = StoredValue(.User.libraryStyle(id: library.parent.pagingLibraryID))
        self._viewModel = StateObject(wrappedValue: PagingLibraryViewModel(
            library: library,
            automaticallyRefreshes: automaticallyRefreshes
        ))
    }

    @ViewBuilder
    private var elementsView: some View {
        AlternateLayoutView {
            Color.clear
        } content: { (frame: FrameAndSafeAreaInsets) in

            let insets: EdgeInsets = if #available(iOS 26, *), isSafeAreaBarApplied {
                frame.safeAreaInsets + 10
            } else {
                .zero + 10
            }

            let grid = CollectionVGrid(
                uniqueElements: viewModel.displayedElements,
                layout: Element.layout(
                    for: libraryStyle,
                    options: libraryStyleOptions,
                    insets: insets
                )
            ) { element in
                element.makeBody(libraryStyle: libraryStyle)
                    #if os(tvOS)
                        .focused($focusedElementID, equals: element.id)
                    #endif
            }
            .onReachedBottomEdge(offset: .offset(300)) {
                guard isTabContentActive else { return }
                if viewModel.isSearchActive {
                    viewModel.getNextSearchPage()
                } else {
                    viewModel.getNextPage()
                }
            }
            .proxy(gridProxy)
            .environment(\.episodeRouteOriginContext, episodeRouteOriginContext)
            #if os(tvOS)
            withInitialGridFocus(grid)
                .background {
                    CollectionVGridLocator(coordinator: gridScrollCoordinator, tabID: episodeRouteTabID)
                        .id(gridLocatorID)
                }
                .ignoresSafeArea(edges: .horizontal)
                .onAppear {
                    recordGridReadiness("grid-view-appeared")
                }
                .onChange(of: viewModel.displayedElements.count) { _, _ in
                    recordGridReadiness("grid-content-count-changed")
                }
            #else
            grid
                .ignoresSafeArea(edges: .horizontal)
            #endif
        }
        .scrollIndicators(.hidden)
        .withViewContext(.isListRowSeparatorVisible)
        .withViewContext(.isThumb)
        #if os(tvOS)
        .focusSection()
        #endif
        .onReceive(tabItemSelected) { event in
            #if DEBUG && os(tvOS)
            LibraryFocusDiagnostics.record(
                "tab-event-received",
                tabID: episodeRouteTabID,
                detail: "active=\(isTabContentActive) root=\(event.isRoot) repeat=\(event.isRepeat)"
            )
            #endif
            if isTabContentActive, event.isRepeat, event.isRoot {
                #if os(tvOS)
                gridProxy.scrollToTop(animated: false)
                focusFirstGridElementForTabEntry()
                #else
                gridProxy.scrollToTop(animated: true)
                #endif
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if isLibraryStyleSectionVisible {
            LibraryStyleSection(
                libraryStyle: storedLibraryStyleBinding,
                options: libraryStyleOptions
            )
        }

        viewModel.library.makeMenuContent(environment: $viewModel.environment)

        Button(L10n.random, systemImage: "dice.fill") {
            viewModel.getRandomItem()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if viewModel.isSearchActive, viewModel.background.is(.searching) {
            ProgressView()
        } else if viewModel.displayedElements.isEmpty {
            ContentUnavailableView(
                viewModel.isSearchActive ? L10n.noResults.localizedCapitalized : L10n.noItems.localizedCapitalized,
                systemImage: viewModel.isSearchActive ? "magnifyingglass" : "rectangle.on.rectangle.slash"
            )
            .focusable(isTabContentActive)
            #if os(tvOS)
            .focused($isEmptyContentFocused)
            #endif
        } else {
            elementsView
        }
    }

    #if os(tvOS)
    private func shouldRefreshItemLibrary(after update: ItemUpdate) -> Bool {
        guard let library = viewModel.library as? ItemLibrary,
              let environment = viewModel.environment as? ItemLibrary.Environment
        else { return false }

        return library.shouldRefreshCollection(after: update, environment: environment)
    }
    #endif

    var body: some View {
        viewModel.library.makeLibraryBody(viewModel: viewModel) {
            ZStack {
                if viewModel.automaticallyRefreshes, viewModel.hasLoadedAutomatically {
                    loadedContent
                } else {
                    switch viewModel.state {
                    case .initial, .refreshing:
                        ProgressView()
                    case .content:
                        loadedContent
                    case .error:
                        viewModel.error.map(ErrorView.init)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(
                \.itemStateStore,
                observesItemState ? userSessionManager.currentSession?.itemStateStore : nil
            )
        }
        .animation(.linear(duration: 0.2), value: viewModel.background.is(.gettingNextPage))
        .animation(.linear(duration: 0.2), value: viewModel.background.is(.searching))
        .animation(.linear(duration: 0.2), value: viewModel.elements)
        .animation(.linear(duration: 0.2), value: viewModel.searchElements)
        .navigationTitle(viewModel.library.parent.displayTitle)
        .onPreferenceChange(IsSafeAreaBarApplied.self) { newValue in
            isSafeAreaBarApplied = newValue
        }
        #if os(iOS)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #endif
        .onChange(of: scenePhase) { _, phase in
            viewModel.setAutomaticRefreshActive(phase == .active)
        }
        .onChange(of: isTabContentActive) { _, active in
            #if DEBUG && os(tvOS)
            LibraryFocusDiagnostics.record("tab-content-active-changed", tabID: episodeRouteTabID, detail: "active=\(active)")
            #endif
            tabContentActivityChanged(active)
        }
        #if os(tvOS)
        .onChange(of: navigationCoordinator.presentedSheet?.route.episodeRouteOrigin) { _, origin in
            episodeRouteOriginChanged(origin)
        }
        .onReceive(
            Notifications[.itemUserDataDidChange].publisher.receive(on: DispatchQueue.main),
            perform: itemUserDataDidChange
        )
        #endif
        .onChange(of: viewModel.environment) {
            viewModel.refreshForEnvironmentChange()
        }
        .onChange(of: libraryStyle) { oldStyle, newStyle in
            if Element.layout(for: oldStyle, options: libraryStyleOptions, insets: .zero) ==
                Element.layout(for: newStyle, options: libraryStyleOptions, insets: .zero)
            {
                gridProxy.layout()
            }
        }
        #if os(tvOS)
        .onChange(of: viewModel.letterScrollTarget) { _, letter in
            savedFocusedElementID = nil
            isLetterRestorePending = false
            _ = scrollToLetter(letter)
        }
        .onChange(of: focusedElementID) { _, elementID in
            #if DEBUG && os(tvOS)
            LibraryFocusDiagnostics.record(
                "grid-focusstate-observed",
                tabID: episodeRouteTabID,
                detail: "value=\(String(describing: elementID)); SwiftUI focus binding observation"
            )
            #endif
            if let elementID {
                savedFocusedElementID = elementID
                if isTabContentFocusable {
                    tabContentFocusHandoff.complete(tabID: episodeRouteTabID)
                }
            }
        }
        .onChange(of: isEmptyContentFocused) { _, isFocused in
            #if DEBUG && os(tvOS)
            LibraryFocusDiagnostics.record(
                "empty-content-focusstate-observed",
                tabID: episodeRouteTabID,
                detail: "focused=\(isFocused); SwiftUI focus binding observation"
            )
            #endif
            guard isFocused, isTabContentFocusable else { return }
            tabContentFocusHandoff.complete(tabID: episodeRouteTabID)
        }
        .onChange(of: viewModel.elements) {
            restoreLetterPositionIfNeeded()
        }
        .onAppear {
            viewModel.setAutomaticRefreshActive(scenePhase == .active)
            gridLocatorID = UUID()
            isLetterRestorePending = viewModel.letterScrollTarget != nil

            DispatchQueue.main.async {
                restoreLetterPositionIfNeeded()
            }
        }
        .onDisappear {
            tabActivationRefreshTask?.cancel()
            tabActivationRefreshTask = nil
            viewModel.setAutomaticRefreshActive(false)
            isLetterRestorePending = viewModel.letterScrollTarget != nil
            setFocusedElementID(nil, reason: "view disappeared reset")
            gridScrollCoordinator.locatorView = nil
            gridScrollCoordinator.collectionView = nil
        }
        #endif
        .onReceive(viewModel.events) { event in
            guard isTabContentActive else { return }
            switch event {
            case let .gotRandomItem(element):
                element.libraryDidSelectElement(router: router, in: namespace)
            }
        }
        .onFirstAppear {
            if viewModel.automaticallyRefreshes {
                viewModel.setAutomaticRefreshActive(scenePhase == .active)
            } else {
                viewModel.refresh()
            }
        }
        #if os(iOS)
        .navigationBarMenuButton(
            isLoading: viewModel.background.is(.gettingNextPage) || viewModel.background.is(.gettingNextSearchPage)
        ) {
            menuContent
        }
        #endif
    }

    #if os(tvOS)
    private func episodeRouteOriginChanged(_ origin: EpisodeRouteIntent.Origin?) {
        guard let origin else {
            guard let pendingEpisodeRouteOrigin else { return }
            self.pendingEpisodeRouteOrigin = nil
            restoreEpisodeRouteOrigin(pendingEpisodeRouteOrigin)
            return
        }

        guard case let .library(tabID, libraryID, _) = origin.source,
              tabID == episodeRouteTabID,
              libraryID == viewModel.id
        else { return }

        pendingEpisodeRouteOrigin = origin
    }

    private func restoreEpisodeRouteOrigin(_ origin: EpisodeRouteIntent.Origin) {
        guard case let .library(tabID, libraryID, originIndex) = origin.source,
              tabID == episodeRouteTabID,
              libraryID == viewModel.id
        else { return }

        let elements = Array(viewModel.displayedElements)
        let exactIndex = elements.firstIndex { element in
            (element as? BaseItemDto)?.id == origin.itemID
        }
        let fallbackIndex = originIndex.flatMap { preferredIndex in
            elements.indices.min { lhs, rhs in
                let leftDistance = abs(lhs - preferredIndex)
                let rightDistance = abs(rhs - preferredIndex)
                return leftDistance == rightDistance ? lhs < rhs : leftDistance < rightDistance
            }
        }
        guard let index = exactIndex ?? fallbackIndex ?? elements.indices.first else {
            setFocusedElementID(nil, reason: "details restoration found no valid item")
            return
        }

        let elementID = elements[index].id
        guard !gridScrollCoordinator.isItemVisible(at: index) else {
            setFocusedElementID(elementID, reason: "details restoration target already visible")
            return
        }

        gridScrollCoordinator.scrollToItem(at: index) {
            guard isTabContentActive else { return }
            setFocusedElementID(elementID, reason: "details restoration after scroll completion")
        }
    }

    private func restoreLetterPositionIfNeeded() {
        guard isTabContentActive, isLetterRestorePending,
              let letter = viewModel.letterScrollTarget,
              let index = viewModel.displayedElements.firstIndex(where: { $0.id == savedFocusedElementID }) ??
              indexOfFirstElement(for: letter)
        else { return }

        isLetterRestorePending = false
        let elementID = viewModel.displayedElements[index].id
        gridScrollCoordinator.scrollToItem(at: index) {
            guard isTabContentActive else { return }
            setFocusedElementID(elementID, reason: "letter restoration after scroll completion")
        }
    }

    @discardableResult
    private func scrollToLetter(_ letter: ItemLetter?) -> Bool {
        guard isTabContentActive, let letter,
              let index = indexOfFirstElement(for: letter)
        else { return false }

        gridScrollCoordinator.scrollToItem(at: index)
        return true
    }

    private func indexOfFirstElement(for letter: ItemLetter) -> Int? {
        let target = letter.value.uppercased()

        return viewModel.displayedElements.firstIndex { element in
            let title = element.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = title.first else { return false }
            let initial = String(first).uppercased()

            if target == "#" {
                return initial.range(of: "^[A-Z]$", options: .regularExpression) == nil
            }

            return initial == target
        }
    }

    private func tabContentActivityChanged(_ isActive: Bool) {
        guard isActive else {
            tabActivationRefreshTask?.cancel()
            tabActivationRefreshTask = nil
            return
        }

        tabActivationRefreshTask?.cancel()
        tabActivationRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, isTabContentActive else { return }
            viewModel.refreshAutomaticallyIfStale()
            tabActivationRefreshTask = nil
        }
    }

    private func itemUserDataDidChange(_ update: ItemUpdate) {
        guard observesItemState,
              !viewModel.automaticallyRefreshes,
              update.userSessionID == userSessionManager.currentSession?.id,
              shouldRefreshItemLibrary(after: update)
        else { return }

        Task {
            await viewModel.refreshCollectionForMembershipChange()
        }
    }

    @ViewBuilder
    private func withInitialGridFocus(_ content: some View) -> some View {
        if let library = viewModel.library as? ItemLibrary,
           library.prefersInitialGridFocus,
           let firstElementID = viewModel.displayedElements.first?.id
        {
            content.defaultFocus($focusedElementID, firstElementID, priority: .userInitiated)
        } else {
            content
        }
    }

    private func focusFirstGridElementForTabEntry() {
        guard isTabContentActive,
              let library = viewModel.library as? ItemLibrary,
              library.prefersInitialGridFocus,
              let firstElementID = viewModel.displayedElements.first?.id
        else { return }

        setFocusedElementID(firstElementID, reason: "root tab-entry event")
    }

    private func setFocusedElementID(_ value: Element.ID?, reason: String) {
        #if DEBUG && os(tvOS)
        LibraryFocusDiagnostics.record(
            "focusstate-request",
            tabID: episodeRouteTabID,
            detail: "value=\(String(describing: value)); reason=\(reason); request only, grant not implied"
        )
        #endif
        focusedElementID = value
    }

    private func recordGridReadiness(_ event: String) {
        #if DEBUG && os(tvOS)
        let collectionView = gridScrollCoordinator.collectionView
        let active = isTabContentActive
        let count = viewModel.displayedElements.count
        let firstID = String(describing: viewModel.displayedElements.first?.id)
        let prefersGridFocus = (viewModel.library as? ItemLibrary)?.prefersInitialGridFocus ?? false
        let isWindowReady = collectionView?.window != nil
        let itemCount = collectionView?.numberOfItems(inSection: 0) ?? -1
        LibraryFocusDiagnostics.record(
            event,
            tabID: episodeRouteTabID,
            detail: "active=\(active) count=\(count) firstID=\(firstID) " +
                "defaultFocus=\(prefersGridFocus) priority=userInitiated windowReady=\(isWindowReady) items=\(itemCount)"
        )
        #endif
    }
    #endif
}

#if os(tvOS)
private final class CollectionVGridScrollCoordinator: ObservableObject {

    weak var locatorView: UIView?

    weak var collectionView: UICollectionView? {
        didSet {
            applyPendingScroll()
        }
    }

    private var pendingIndex: Int?
    private var pendingFocus: (() -> Void)?

    func isItemVisible(at index: Int) -> Bool {
        guard let collectionView,
              collectionView.window != nil,
              index >= 0
        else { return false }

        return collectionView.indexPathsForVisibleItems.contains(
            IndexPath(item: index, section: 0)
        )
    }

    func scrollToItem(at index: Int, onScrolled: (() -> Void)? = nil) {
        pendingIndex = index
        pendingFocus = onScrolled
        applyPendingScroll()
    }

    private func applyPendingScroll() {
        guard let collectionView,
              collectionView.window != nil,
              !collectionView.bounds.isEmpty,
              let index = pendingIndex,
              index >= 0,
              collectionView.numberOfSections > 0,
              index < collectionView.numberOfItems(inSection: 0)
        else { return }

        let focus = pendingFocus
        pendingIndex = nil
        pendingFocus = nil
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .top,
            animated: false
        )
        collectionView.layoutIfNeeded()
        if let focus {
            DispatchQueue.main.async(execute: focus)
        }
    }
}

private struct CollectionVGridLocator: UIViewRepresentable {

    let coordinator: CollectionVGridScrollCoordinator
    let tabID: String?

    final class LocatorView: UIView {
        var locate: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            locate?()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            locate?()
        }
    }

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView(frame: .zero)
        view.isUserInteractionEnabled = false
        coordinator.locatorView = view
        coordinator.collectionView = nil
        return view
    }

    func updateUIView(_ uiView: LocatorView, context: Context) {
        uiView.locate = { [weak uiView] in
            DispatchQueue.main.async {
                guard let uiView,
                      self.coordinator.locatorView === uiView,
                      uiView.window != nil
                else { return }
                let collectionView = self.findCollectionView(near: uiView)
                if self.coordinator.collectionView !== collectionView, let collectionView {
                    #if DEBUG
                    let firstCell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0))
                    let firstCellVisible = collectionView.indexPathsForVisibleItems.contains(IndexPath(item: 0, section: 0))
                    let itemCount = collectionView.numberOfItems(inSection: 0)
                    let bounds = collectionView.bounds
                    LibraryFocusDiagnostics.record(
                        "grid-collection-mounted",
                        tabID: self.tabID,
                        detail: "windowReady=true bounds=\(bounds) items=\(itemCount) " +
                            "firstCellReady=\(firstCell != nil) firstCellVisible=\(firstCellVisible)"
                    )
                    #endif
                }
                self.coordinator.collectionView = collectionView
            }
        }
        uiView.locate?()
    }

    private func findCollectionView(near view: UIView) -> UICollectionView? {
        var ancestor = view.superview

        while let current = ancestor {
            if let collectionView = firstCollectionView(in: current) {
                return collectionView
            }
            ancestor = current.superview
        }

        return nil
    }

    private func firstCollectionView(in view: UIView) -> UICollectionView? {
        if view is any _UICollectionVGrid {
            return view.subviews.compactMap { $0 as? UICollectionView }.first
        }

        for subview in view.subviews {
            if let collectionView = firstCollectionView(in: subview) {
                return collectionView
            }
        }

        return nil
    }
}
#endif
