//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import SwiftUI

struct PagingLibraryView<Library: PagingLibrary>: View where Library.Element: LibraryElement {

    typealias Element = Library.Element

    @Default(.Customization.Library.rememberLayout)
    private var rememberIndividualLibraryStyle
    @Default(.Customization.Library.style)
    private var defaultLibraryStyle

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

    @State
    private var savedFocusedElementID: Element.ID?

    @State
    private var gridLocatorID = UUID()

    @State
    private var isLetterRestorePending: Bool = false
    #endif
    @StateObject
    private var viewModel: PagingLibraryViewModel<Library>

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

    init(library: Library) {
        self._parentLibraryStyle = StoredValue(.User.libraryStyle(id: library.parent.pagingLibraryID))
        self._viewModel = StateObject(wrappedValue: PagingLibraryViewModel(library: library))
    }

    @ViewBuilder
    private var elementsView: some View {
        AlternateLayoutView {
            Color.clear
        } content: { frame in

            let insets: EdgeInsets = if #available(iOS 26, *), isSafeAreaBarApplied {
                frame.safeAreaInsets + 10
            } else {
                .zero + 10
            }

            CollectionVGrid(
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
                if viewModel.isSearchActive {
                    viewModel.getNextSearchPage()
                } else {
                    viewModel.getNextPage()
                }
            }
            .proxy(gridProxy)
            #if os(tvOS)
                .background {
                    CollectionVGridLocator(coordinator: gridScrollCoordinator)
                        .id(gridLocatorID)
                }
            #endif
                .ignoresSafeArea(edges: .horizontal)
        }
        .scrollIndicators(.hidden)
        .withViewContext(.isListRowSeparatorVisible)
        .withViewContext(.isThumb)
        #if os(tvOS)
            .focusSection()
        #endif
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    #if os(tvOS)
                    gridProxy.scrollToTop(animated: false)
                    focusedElementID = nil
                    DispatchQueue.main.async {
                        focusedElementID = viewModel.displayedElements.first?.id
                    }
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

    var body: some View {
        viewModel.library.makeLibraryBody(viewModel: viewModel) {
            ZStack {
                switch viewModel.state {
                case .initial, .refreshing:
                    ProgressView()
                case .content:
                    if viewModel.isSearchActive, viewModel.background.is(.searching) {
                        ProgressView()
                    } else if viewModel.displayedElements.isEmpty {
                        ContentUnavailableView(
                            viewModel.isSearchActive ? L10n.noResults.localizedCapitalized : L10n.noItems.localizedCapitalized,
                            systemImage: viewModel.isSearchActive ? "magnifyingglass" : "rectangle.on.rectangle.slash"
                        )
                        .focusable()
                    } else {
                        elementsView
                    }
                case .error:
                    viewModel.error.map(ErrorView.init)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let elementID {
                savedFocusedElementID = elementID
            }
        }
        .onChange(of: viewModel.elements) {
            restoreLetterPositionIfNeeded()
        }
        .onAppear {
            gridLocatorID = UUID()
            isLetterRestorePending = viewModel.letterScrollTarget != nil

            DispatchQueue.main.async {
                restoreLetterPositionIfNeeded()
            }
        }
        .onDisappear {
            isLetterRestorePending = viewModel.letterScrollTarget != nil
            focusedElementID = nil
            gridScrollCoordinator.locatorView = nil
            gridScrollCoordinator.collectionView = nil
        }
        #endif
        .onReceive(viewModel.events) { event in
                switch event {
                case let .gotRandomItem(element):
                    element.libraryDidSelectElement(router: router, in: namespace)
                }
            }
            .onFirstAppear {
                viewModel.refresh()
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
    private func restoreLetterPositionIfNeeded() {
        guard isLetterRestorePending,
              let letter = viewModel.letterScrollTarget,
              let index = viewModel.displayedElements.firstIndex(where: { $0.id == savedFocusedElementID }) ??
              indexOfFirstElement(for: letter)
        else { return }

        isLetterRestorePending = false
        let elementID = viewModel.displayedElements[index].id
        gridScrollCoordinator.scrollToItem(at: index) {
            focusedElementID = elementID
        }
    }

    @discardableResult
    private func scrollToLetter(_ letter: ItemLetter?) -> Bool {
        guard let letter,
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
                self.coordinator.collectionView = self.findCollectionView(near: uiView)
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
