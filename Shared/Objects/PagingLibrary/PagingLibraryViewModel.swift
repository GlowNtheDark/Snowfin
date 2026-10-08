//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import IdentifiedCollections
import JellyfinAPI

let defaultPagingLibraryPageSize = 50

@MainActor
@Stateful(conformances: [WithRefresh.self])
class PagingLibraryViewModel<Library: PagingLibrary>: ViewModel, @MainActor Identifiable {

    typealias Background = _BackgroundActions
    typealias Element = Library.Element
    typealias Environment = Library.Environment

    @CasePathable
    enum Action {
        case refresh
        case getNextPage
        case getRandomItem
        case getNextSearchPage
        case search(query: String)

        case _actuallyGetNextPage

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .content)
                    .whenBackground(.refreshing)
            case .getNextPage:
                .none
            case .getRandomItem:
                .background(.gettingRandomItem)
            case .getNextSearchPage:
                .background(.gettingNextSearchPage)
            case .search:
                .background(.searching)
                    .onRepeat(.cancel)
            case ._actuallyGetNextPage:
                .background(.gettingNextPage)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case gettingNextPage
        case gettingRandomItem
        case gettingNextSearchPage
        case searching
    }

    enum Event {
        case gotRandomItem(Element)
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    var elements: IdentifiedArrayOf<Element>
    @Published
    var environment: Environment {
        didSet {
            if automaticallyRefreshes, oldValue != environment {
                queryGeneration += 1
                collectionGeneration += 1
                requestAutomaticRefresh()
            }
        }
    }

    @Published
    var searchElements: IdentifiedArrayOf<Element>
    @Published
    var searchQuery: String = ""
    @Published
    var letterScrollTarget: ItemLetter?

    let library: Library
    let pageSize: Int
    let automaticallyRefreshes: Bool
    let refreshesForItemStateChanges: Bool

    // Opted into only by the retained tvOS TV Shows tab. A successful empty
    // response counts as loaded; collection emptiness is not a loading flag.
    @Published
    private(set) var hasLoadedAutomatically = false
    private var lastAutomaticRefresh = Date.distantPast
    private var automaticRefreshActive = false
    private var automaticRefreshPending = false
    private var automaticRefreshTask: AnyCancellable?
    private var queryGeneration = 0
    private var collectionGeneration = 0
    private var lastHomeCollectionRefresh = Date.distantPast
    private let automaticRefreshInterval: TimeInterval = 300

    private var hasNextPage: Bool
    private var hasNextSearchPage: Bool
    private var itemUserDataRefreshTask: AnyCancellable?
    private var lastItemUserDataRefresh = Date.distantPast
    private var userSessionID: UUID?
    private var lastItemUpdateRevisions: [String: UInt64] = [:]
    private var itemUpdateRevisionOrder: [String] = []
    private let maximumRememberedItemUpdateRevisions = 512

    var id: String {
        library.parent.pagingLibraryID
    }

    var isSearchActive: Bool {
        normalizedSearchQuery.isNotEmpty
    }

    var isSearchSupported: Bool {
        searchableLibrary != nil
    }

    var displayedElements: IdentifiedArrayOf<Element> {
        isSearchActive ? searchElements : elements
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchableLibrary: (any SearchablePagingLibrary<Element, Environment>)? {
        library as? any SearchablePagingLibrary<Element, Environment>
    }

    init(
        library: Library,
        pageSize: Int = defaultPagingLibraryPageSize,
        automaticallyRefreshes: Bool = false,
        refreshesForItemStateChanges: Bool = false
    ) {
        self.automaticallyRefreshes = automaticallyRefreshes
        self.refreshesForItemStateChanges = refreshesForItemStateChanges
        self.elements = IdentifiedArray([], uniquingIDsWith: { existing, _ in existing })
        self.environment = library.environment ?? .default
        self.searchElements = IdentifiedArray([], uniquingIDsWith: { existing, _ in existing })
        self.hasNextPage = library.hasNextPage
        self.hasNextSearchPage = false
        self.library = library
        self.pageSize = pageSize

        super.init()
        userSessionID = userSession?.id

        Notifications[.didDeleteItem]
            .publisher
            .sink { [weak self] id in
                guard let self else { return }
                if refreshesForItemStateChanges {
                    collectionGeneration += 1
                } else {
                    removeDeletedItem(withID: id)
                }
                invalidateAutomaticCollection()
            }
            .store(in: &cancellables)

        Notifications[.itemUserDataDidChange]
            .publisher
            .sink { [weak self] update in
                guard let self else { return }
                guard update.userSessionID == userSessionID else { return }
                guard acceptItemUpdate(update) else { return }

                updateItemUserData(update)
                if let userData = update.userDataPatch {
                    library.onItemUserDataChanged(viewModel: self, userData: userData)
                }
                if refreshesForItemStateChanges,
                   shouldRefreshCollection(after: update)
                {
                    // Reject any snapshot that began before this membership/order change.
                    collectionGeneration += 1
                }
                invalidateAutomaticCollection(
                    requestRefresh: library.shouldRefreshCollection(
                        after: update,
                        environment: environment
                    )
                )
            }
            .store(in: &cancellables)

        if automaticallyRefreshes {
            Publishers.MergeMany([
                Notifications[.itemMetadataDidChange].publisher.map { _ in () }.eraseToAnyPublisher(),
                Notifications[.didRequestGlobalRefresh].publisher.map { _ in () }.eraseToAnyPublisher(),
                Notifications[.didChangeServerConnection].publisher.map { _ in () }.eraseToAnyPublisher(),
            ])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.invalidateAutomaticCollection()
            }
            .store(in: &cancellables)

            Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.refreshAutomaticallyIfStale()
                }
                .store(in: &cancellables)
        }

        $searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.search(query: query)
            }
            .store(in: &cancellables)
    }

    func setAutomaticRefreshActive(_ active: Bool) {
        guard automaticallyRefreshes else { return }
        automaticRefreshActive = active
        if active {
            refreshAutomaticallyIfStale()
        }
    }

    func refreshAutomaticallyIfStale() {
        guard automaticallyRefreshes, automaticRefreshActive else { return }
        // A timer or tab entry during a fetch is not a new invalidation.
        guard automaticRefreshTask == nil else { return }
        if automaticRefreshPending || Date.now.timeIntervalSince(lastAutomaticRefresh) >= automaticRefreshInterval {
            requestAutomaticRefresh()
        }
    }

    private func invalidateAutomaticCollection(requestRefresh: Bool = true) {
        guard automaticallyRefreshes else { return }
        // Reject snapshots started before an accepted user-data change/deletion.
        collectionGeneration += 1
        if requestRefresh || !hasLoadedAutomatically {
            requestAutomaticRefresh()
        }
    }

    private func requestAutomaticRefresh() {
        automaticRefreshPending = true
        guard automaticRefreshActive, automaticRefreshTask == nil else { return }

        automaticRefreshTask = Task { @MainActor [weak self] in
            // Batch bursts of related notifications before starting network work.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            defer { automaticRefreshTask = nil }

            while automaticRefreshPending, automaticRefreshActive, !Task.isCancelled {
                automaticRefreshPending = false
                if hasLoadedAutomatically {
                    await background.refresh()
                } else {
                    await refresh()
                }
            }
        }
        .asAnyCancellable()
    }

    private func didLoadAutomaticCollection() {
        guard automaticallyRefreshes else { return }
        hasLoadedAutomatically = true
        lastAutomaticRefresh = .now
    }

    func refreshForEnvironmentChange() {
        if automaticallyRefreshes {
            // Collection invalidation is synchronous in environment.didSet, so
            // an older response cannot publish while waiting for view updates.
            if isSearchActive {
                search(query: normalizedSearchQuery)
            }
        } else if isSearchActive {
            search(query: normalizedSearchQuery)
        } else {
            refresh()
        }
    }

    private func removeDeletedItem(withID id: String) {
        removeDeletedItem(withID: id, from: &elements)
        removeDeletedItem(withID: id, from: &searchElements)
    }

    private func removeDeletedItem(
        withID id: String,
        from elements: inout IdentifiedArrayOf<Element>
    ) {
        elements.removeAll { element in
            if let item = element as? BaseItemDto {
                return item.id == id
            }

            if let user = element as? UserDto {
                return user.id == id
            }

            if let elementID = element.id as? String {
                return elementID == id
            }

            if let elementID = element.id as? String? {
                return elementID == id
            }

            return false
        }
    }

    private func updateItemUserData(_ update: ItemUpdate) {
        guard let userData = update.userDataPatch,
              containsItem(withID: update.itemID)
        else { return }

        updateItemUserData(userData, itemID: update.itemID, in: &elements)
        updateItemUserData(userData, itemID: update.itemID, in: &searchElements)
    }

    private func acceptItemUpdate(_ update: ItemUpdate) -> Bool {
        guard update.revision > (lastItemUpdateRevisions[update.itemID] ?? 0) else { return false }
        lastItemUpdateRevisions[update.itemID] = update.revision
        itemUpdateRevisionOrder.removeAll { $0 == update.itemID }
        itemUpdateRevisionOrder.append(update.itemID)

        while itemUpdateRevisionOrder.count > maximumRememberedItemUpdateRevisions {
            let evictedItemID = itemUpdateRevisionOrder.removeFirst()
            lastItemUpdateRevisions[evictedItemID] = nil
        }

        return true
    }

    private func updateItemUserData(
        _ userData: UserItemDataDto,
        itemID: String,
        in elements: inout IdentifiedArrayOf<Element>
    ) {
        for index in elements.indices {
            guard var item = elements[index] as? BaseItemDto,
                  item.id == itemID
            else { continue }

            item.userData = item.userData?.mergingNonNilFields(from: userData, itemID: itemID) ?? userData
            elements[index] = item as! Element
        }
    }

    func containsItem(withID itemID: String) -> Bool {
        elements.contains { ($0 as? BaseItemDto)?.id == itemID } ||
            searchElements.contains { ($0 as? BaseItemDto)?.id == itemID }
    }

    func shouldRefreshCollection(after update: ItemUpdate) -> Bool {
        let shouldRefresh = library.shouldRefreshCollection(
            after: update,
            environment: environment,
            containsItem: containsItem(withID: update.itemID)
        )
        guard shouldRefresh else { return false }

        let minimumInterval = library.homeCollectionRefreshMinimumInterval(after: update)
        return Date.now.timeIntervalSince(lastHomeCollectionRefresh) >= minimumInterval
    }

    func invalidateSearchCollection(after update: ItemUpdate) -> Bool {
        guard library.shouldRefreshSearchCollection(after: update, environment: environment) else {
            return false
        }

        // Invalidate an older in-flight query before the targeted replacement starts.
        collectionGeneration += 1
        return true
    }

    func shouldRefreshCollection(afterDeletingItemID itemID: String) -> Bool {
        containsItem(withID: itemID)
    }

    func refreshCollectionForHomeChange() async {
        collectionGeneration += 1
        lastHomeCollectionRefresh = .now
        await background.refresh()
    }

    func refreshCollectionForSearchChange() async {
        await background.refresh()
    }

    func scheduleRefreshForItemUserData(
        debounce: TimeInterval = 0.35,
        minimumInterval: TimeInterval = 5
    ) {
        guard Date.now.timeIntervalSince(lastItemUserDataRefresh) >= minimumInterval else {
            return
        }

        itemUserDataRefreshTask?.cancel()
        itemUserDataRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if debounce > 0 {
                try? await Task.sleep(for: .seconds(debounce))
            }

            guard !Task.isCancelled else { return }

            await self.background.refresh()
            self.lastItemUserDataRefresh = Date.now
            self.itemUserDataRefreshTask = nil
        }
        .asAnyCancellable()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        hasNextPage = true

        if StateTask.isBackground || (automaticallyRefreshes && hasLoadedAutomatically) {
            try await replaceElements()
        } else {
            elements.removeAll()
            try await __actuallyGetNextPage()
        }
    }

    @Function(\Action.Cases.getNextPage)
    private func _getNextPage() async throws {
        guard hasNextPage else { return }
        // The retained TV library already fetches the entire collection. Do not
        // let a bottom-edge callback start another request during replacement.
        guard !automaticallyRefreshes || automaticRefreshTask == nil else { return }
        await _actuallyGetNextPage()
    }

    @Function(\Action.Cases._actuallyGetNextPage)
    private func __actuallyGetNextPage() async throws {
        guard hasNextPage else { return }

        let generation = collectionGeneration
        let nextPageElements = try await retrievePage(offset: elements.count)

        guard !Task.isCancelled, generation == collectionGeneration else { return }

        hasNextPage = !library.loadsEntireCollection && !(nextPageElements.count < pageSize)
        elements.append(contentsOf: nextPageElements)
        didLoadAutomaticCollection()
    }

    private func replaceElements() async throws {
        let generation = collectionGeneration
        let newElements = try await retrievePage(offset: 0)

        guard !Task.isCancelled, generation == collectionGeneration else { return }

        hasNextPage = !library.loadsEntireCollection && !(newElements.count < pageSize)
        elements = IdentifiedArray(newElements, uniquingIDsWith: { existing, _ in existing })
        didLoadAutomaticCollection()
    }

    private func retrievePage(offset: Int) async throws -> [Element] {
        try await library.retrievePage(
            environment: environment,
            pageState: pageState(offset: offset, pageSize: pageSize)
        )
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        guard query.isNotEmpty,
              searchableLibrary != nil
        else {
            hasNextSearchPage = false
            searchElements.removeAll()
            return
        }

        searchElements.removeAll()
        hasNextSearchPage = true
        try await retrieveNextSearchPage(query: query)
    }

    @Function(\Action.Cases.getNextSearchPage)
    private func _getNextSearchPage() async throws {
        guard isSearchActive,
              hasNextSearchPage,
              !background.is(.searching)
        else { return }

        try await retrieveNextSearchPage(query: normalizedSearchQuery)
    }

    private func retrieveNextSearchPage(query: String) async throws {
        guard let searchableLibrary,
              hasNextSearchPage
        else { return }

        let generation = queryGeneration
        let nextPageElements = try await searchableLibrary.retrieveSearchPage(
            query: query,
            environment: environment,
            pageState: pageState(offset: searchElements.count, pageSize: pageSize)
        )

        guard !Task.isCancelled,
              generation == queryGeneration,
              query == normalizedSearchQuery
        else { return }

        hasNextSearchPage = !(nextPageElements.count < pageSize)
        searchElements.append(contentsOf: nextPageElements)
    }

    @Function(\Action.Cases.getRandomItem)
    private func _getRandomItem() async throws {
        let randomElement: Element? = if let randomLibrary = library as? any WithRandomElementLibrary<Element, Environment> {
            try await randomLibrary.retrieveRandomElement(
                environment: environment,
                pageState: pageState(offset: 0, pageSize: 1)
            )
        } else {
            elements.randomElement()
        }

        guard !Task.isCancelled, let randomElement else { return }

        events.send(.gotRandomItem(randomElement))
    }

    private func pageState(offset: Int, pageSize: Int) throws -> LibraryPageState {
        try .init(
            pageOffset: offset,
            pageSize: pageSize,
            userSession: requireUserSession()
        )
    }
}

extension PagingLibraryViewModel where Element: LibraryElement {

    var libraryStyleOptions: LibraryStyleOptions {
        library.resolvedLibraryStyleOptions(
            environment: environment,
            elements: displayedElements
        )
    }
}
