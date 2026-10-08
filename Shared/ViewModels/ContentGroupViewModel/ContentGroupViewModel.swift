//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI

@MainActor
@Stateful
final class ContentGroupViewModel<Provider: ContentGroupProvider>: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case refreshHomeCollections

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .content)
                    .whenBackground(.refreshing)
            case .refreshHomeCollections:
                .background(.refreshingHomeCollections)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case refreshingHomeCollections
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var groups: [any ContentGroup] = []

    private var candidateGroups: [any ContentGroup] = []
    private var lastRefreshDate = Date.distantPast
    private var lastRefreshSignalDate = Date.distantPast
    private var pendingHomeCollectionIDs = Set<String>()
    private var pendingSearchCollectionIDs = Set<String>()
    @Published
    private(set) var isRefreshingHomeCollections = false
    private var isRefreshingSearchCollections = false

    #if os(tvOS)
    private var homeRefreshPending = false
    private var homeRefreshRunning = false
    private var defersHomeRefresh = false
    #endif

    private var hasPendingRefreshSignals: Bool {
        lastRefreshSignalDate > lastRefreshDate
    }

    var provider: Provider

    init(provider: Provider) {
        self.provider = provider
        super.init()

        #if os(tvOS)
        Notifications[.itemUserDataDidChange]
            .publisher
            .filter { [weak self] update in
                guard let self,
                      update.userSessionID == userSession?.id
                else { return false }
                return true
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                if provider is DefaultContentGroupProvider {
                    invalidateHomeCollections(after: update)
                } else if provider is SearchContentGroupProvider {
                    invalidateSearchCollections(after: update)
                }
            }
            .store(in: &cancellables)
        #else
        Notifications[.itemUserDataDidChange]
            .publisher
            .filter { [weak self] update in
                guard let self,
                      update.userSessionID == userSession?.id
                else { return false }
                if case .userData = update.change {
                    return true
                }
                return false
            }
            .sink { [weak self] _ in
                self?.lastRefreshSignalDate = Date.now
            }
            .store(in: &cancellables)
        #endif

        let metadataChanges = Notifications[.itemMetadataDidChange]
            .publisher
            .map { _ in () }
            .eraseToAnyPublisher()

        metadataChanges
        #if os(tvOS)
        .receive(on: DispatchQueue.main)
        #endif
        .sink { [weak self] _ in
            self?.lastRefreshSignalDate = Date.now
            #if os(tvOS)
            self?.invalidateHome()
            #endif
        }
        .store(in: &cancellables)

        #if os(tvOS)
        if provider is DefaultContentGroupProvider {
            Publishers.MergeMany([
                Notifications[.didRequestGlobalRefresh].publisher.map { _ in () }.eraseToAnyPublisher(),
            ])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastRefreshSignalDate = Date.now
                self?.invalidateHome()
            }
            .store(in: &cancellables)

            Notifications[.didDeleteItem]
                .publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] itemID in
                    self?.invalidateHomeCollections(afterDeletingItemID: itemID)
                }
                .store(in: &cancellables)
        }
        #endif
    }

    #if os(tvOS)
    private func invalidateHome() {
        guard provider is DefaultContentGroupProvider else { return }
        homeRefreshPending = true
        refreshHomeIfPending()
    }

    private func refreshHomeIfPending() {
        let starts = homeRefreshPending && !defersHomeRefresh && !homeRefreshRunning && !candidateGroups.isEmpty
        guard starts else { return }
        homeRefreshRunning = true
        Task { [weak self] in
            guard let self else { return }
            defer { homeRefreshRunning = false }
            // Signals arriving during a fetch require one follow-up fetch.
            while homeRefreshPending {
                homeRefreshPending = false
                await background.refresh()
            }
        }
    }

    private func invalidateHomeCollections(after update: ItemUpdate) {
        guard provider is DefaultContentGroupProvider else { return }

        let affectedGroupIDs = candidateGroups.compactMap { group -> String? in
            guard let group = group as? any HomeCollectionInvalidatableContentGroup,
                  group.shouldRefreshHomeCollection(after: update)
            else { return nil }
            return group.id
        }
        guard affectedGroupIDs.isNotEmpty else { return }

        lastRefreshSignalDate = .now
        pendingHomeCollectionIDs.formUnion(affectedGroupIDs)
        refreshHomeCollectionsIfPending()
    }

    private func invalidateHomeCollections(afterDeletingItemID itemID: String) {
        guard provider is DefaultContentGroupProvider else { return }

        let affectedGroupIDs = candidateGroups.compactMap { group -> String? in
            guard let group = group as? any HomeCollectionInvalidatableContentGroup,
                  group.shouldRefreshHomeCollection(afterDeletingItemID: itemID)
            else { return nil }
            return group.id
        }
        guard affectedGroupIDs.isNotEmpty else { return }

        lastRefreshSignalDate = .now
        pendingHomeCollectionIDs.formUnion(affectedGroupIDs)
        refreshHomeCollectionsIfPending()
    }

    private func invalidateSearchCollections(after update: ItemUpdate) {
        guard provider is SearchContentGroupProvider else { return }

        let affectedGroupIDs = candidateGroups.compactMap { group -> String? in
            guard let group = group as? any SearchCollectionInvalidatableContentGroup,
                  group.invalidateSearchCollection(after: update)
            else { return nil }
            return group.id
        }
        guard affectedGroupIDs.isNotEmpty else { return }

        lastRefreshSignalDate = .now
        pendingSearchCollectionIDs.formUnion(affectedGroupIDs)
        refreshSearchCollectionsIfPending()
    }

    private func refreshSearchCollectionsIfPending() {
        guard provider is SearchContentGroupProvider,
              !isRefreshingSearchCollections,
              !pendingSearchCollectionIDs.isEmpty
        else { return }

        isRefreshingSearchCollections = true
        Task { [weak self] in
            guard let self else { return }
            while !pendingSearchCollectionIDs.isEmpty {
                let groupIDs = pendingSearchCollectionIDs
                pendingSearchCollectionIDs.removeAll()
                let groups = candidateGroups.compactMap { group -> (any SearchCollectionInvalidatableContentGroup)? in
                    guard groupIDs.contains(group.id) else { return nil }
                    return group as? any SearchCollectionInvalidatableContentGroup
                }

                await withTaskGroup(of: Void.self) { taskGroup in
                    for group in groups {
                        taskGroup.addTask {
                            await group.refreshSearchCollection()
                        }
                    }
                }
                resolveGroups()
            }
            lastRefreshDate = .now
            isRefreshingSearchCollections = false
        }
    }

    private func refreshHomeCollectionsIfPending() {
        guard provider is DefaultContentGroupProvider,
              !defersHomeRefresh,
              !isRefreshingHomeCollections,
              !pendingHomeCollectionIDs.isEmpty
        else { return }

        isRefreshingHomeCollections = true
        Task { [weak self] in
            guard let self else { return }
            while !pendingHomeCollectionIDs.isEmpty {
                await background.refreshHomeCollections()
            }
            lastRefreshDate = .now
            isRefreshingHomeCollections = false
        }
    }

    func setDefersHomeRefresh(_ deferred: Bool) {
        defersHomeRefresh = deferred
        if !deferred {
            refreshHomeIfPending()
            refreshHomeCollectionsIfPending()
        }
    }
    #endif

    func refreshIfNeeded(
        sinceLastDisappear interval: TimeInterval,
        staleThreshold: TimeInterval = 60
    ) {
        guard interval > staleThreshold || hasPendingRefreshSignals else { return }

        background.refresh()
    }

    func refreshIfPendingChanges() {
        guard hasPendingRefreshSignals else { return }

        refresh()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        #if os(tvOS)
        let refreshStartedAt = Date.now
        #endif
        if StateTask.isBackground {
            try await backgroundRefresh()
        } else {
            try await fullRefresh()
        }

        #if os(tvOS)
        lastRefreshDate = provider is DefaultContentGroupProvider ? refreshStartedAt : Date.now
        refreshHomeIfPending()
        refreshHomeCollectionsIfPending()
        #else
        lastRefreshDate = Date.now
        #endif
    }

    private func getViewModel(for group: some ContentGroup) -> any WithRefresh {
        group.viewModel
    }

    private func resolveGroups() {
        groups = candidateGroups
            .filter(\._shouldBeResolved)
    }

    private func refreshViewModels(
        for groups: [any ContentGroup],
        inBackground: Bool
    ) async throws {
        let viewModels = groups.map { getViewModel(for: $0) }
            .uniqued { ObjectIdentifier($0 as AnyObject) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for viewModel in viewModels {
                group.addTask {
                    if inBackground {
                        await viewModel.background.refresh()
                    } else {
                        await viewModel.refresh()
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func backgroundRefresh() async throws {
        try await refreshViewModels(
            for: candidateGroups,
            inBackground: true
        )

        resolveGroups()
    }

    private func fullRefresh() async throws {

        self.groups = []
        self.candidateGroups = []

        let newGroups = try await provider.makeGroups(environment: provider.environment)

        candidateGroups = newGroups

        do {
            try await refreshViewModels(
                for: newGroups,
                inBackground: false
            )
        } catch {
            candidateGroups = []
            throw error
        }

        resolveGroups()
    }

    @Function(\Action.Cases.refreshHomeCollections)
    private func _refreshHomeCollections() async {
        while !pendingHomeCollectionIDs.isEmpty {
            let groupIDs = pendingHomeCollectionIDs
            pendingHomeCollectionIDs.removeAll()
            let groups = candidateGroups.compactMap { group -> (any HomeCollectionInvalidatableContentGroup)? in
                guard groupIDs.contains(group.id) else { return nil }
                return group as? any HomeCollectionInvalidatableContentGroup
            }

            await withTaskGroup(of: Void.self) { taskGroup in
                for group in groups {
                    taskGroup.addTask {
                        await group.refreshHomeCollection()
                    }
                }
            }
            resolveGroups()
        }
    }
}
