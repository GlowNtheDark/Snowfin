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
@Stateful
final class ContentGroupViewModel<Provider: ContentGroupProvider>: ViewModel {

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .to(.refreshing, then: .content)
                .whenBackground(.refreshing)
        }
    }

    enum BackgroundState {
        case refreshing
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

        Publishers.Merge(
            Notifications[.itemUserDataDidChange].publisher.map { _ in () },
            Notifications[.itemMetadataDidChange].publisher.map { _ in () }
        )
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
                Notifications[.didSendStopReport].publisher.map { _ in () }.eraseToAnyPublisher(),
                Notifications[.didRequestGlobalRefresh].publisher.map { _ in () }.eraseToAnyPublisher(),
                Notifications[.didDeleteItem].publisher.map { _ in () }.eraseToAnyPublisher(),
            ])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastRefreshSignalDate = Date.now
                self?.invalidateHome()
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

    func setDefersHomeRefresh(_ deferred: Bool) {
        defersHomeRefresh = deferred
        if !deferred {
            refreshHomeIfPending()
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

        try await refreshViewModels(
            for: newGroups,
            inBackground: false
        )

        candidateGroups = newGroups
        resolveGroups()
    }
}
