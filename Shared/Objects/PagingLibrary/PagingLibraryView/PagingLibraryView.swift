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
    private var isElementsFocused: Bool

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
                }
            #endif
                .ignoresSafeArea(edges: .vertical)
        }
        .scrollIndicators(.hidden)
        .withViewContext(.isListRowSeparatorVisible)
        .withViewContext(.isThumb)
        #if os(tvOS)
            .focusSection()
            .focused($isElementsFocused)
        #endif
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    #if os(tvOS)
                    gridProxy.scrollToTop(animated: false)
                    requestElementsFocus()
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
            isLetterRestorePending = false
            _ = scrollToLetter(letter)
        }
        .onChange(of: viewModel.elements) {
            restoreLetterPositionIfNeeded()
        }
        .onAppear {
            isLetterRestorePending = viewModel.letterScrollTarget != nil

            DispatchQueue.main.async {
                restoreLetterPositionIfNeeded()
            }
        }
        .onDisappear {
            isLetterRestorePending = viewModel.letterScrollTarget != nil
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
    private func requestElementsFocus() {
        isElementsFocused = false

        DispatchQueue.main.async {
            isElementsFocused = true
        }
    }

    private func restoreLetterPositionIfNeeded() {
        guard isLetterRestorePending,
              let letter = viewModel.letterScrollTarget,
              let index = indexOfFirstElement(for: letter)
        else { return }

        isLetterRestorePending = false
        requestElementsFocus()

        // Let focus restoration finish before restoring the collection offset.
        // Otherwise tvOS can immediately scroll the grid back to its focused item.
        DispatchQueue.main.async {
            gridScrollCoordinator.scrollToItem(at: index)
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

    weak var collectionView: UICollectionView? {
        didSet {
            applyPendingScroll()
        }
    }

    private var pendingIndex: Int?

    func scrollToItem(at index: Int) {
        pendingIndex = index
        applyPendingScroll()
    }

    private func applyPendingScroll() {
        guard let collectionView,
              let index = pendingIndex,
              index >= 0,
              index < collectionView.numberOfItems(inSection: 0)
        else { return }

        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .top,
            animated: false
        )
        pendingIndex = nil
    }
}

private struct CollectionVGridLocator: UIViewRepresentable {

    let coordinator: CollectionVGridScrollCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            coordinator.collectionView = findCollectionView(near: uiView)
        }
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
        if let collectionView = view as? UICollectionView {
            return collectionView
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
