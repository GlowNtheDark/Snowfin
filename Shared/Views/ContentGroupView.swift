//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

struct ContentGroupView<Provider: ContentGroupProvider>: View {

    @Router
    private var router

    @State
    private var contentGroupOptions: ContentGroupParentOption = .init()

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel: ContentGroupViewModel<Provider>

    #if os(tvOS)
    @State
    private var pendingFirstGroupFocus = false
    @Environment(\.registerHomeFocus)
    private var registerHomeFocus
    @State
    private var homeFocusRows: [HomeFocusRow] = []

    private var isHome: Bool {
        viewModel.provider is DefaultContentGroupProvider
    }

    private func resolveHomeReturn() {
        guard isHome, router.isRootOfPath, !viewModel.background.is(.refreshing) else { return }
        focusCoordinator.resolveHomeReturn(rows: homeFocusRows)
    }
    #endif

    @TabItemSelected
    private var tabItemSelected

    init(provider: Provider) {
        _viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
    }

    #if os(tvOS)
    private func resolveFirstGroupFocus(using proxy: ScrollViewProxy) {
        guard pendingFirstGroupFocus,
              let firstGroup = viewModel.groups.first
        else { return }

        pendingFirstGroupFocus = false
        proxy.scrollTo("top", anchor: .top)
        DispatchQueue.main.async {
            focusCoordinator.focus(firstGroup.id)
        }
    }
    #endif

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    ContentGroupVStack(groups: viewModel.groups)
                        .edgePadding(contentGroupOptions.contains(.ignoreSafeAreaTop) ? .bottom : .vertical)
                        .onPreferenceChange(ContentGroupCustomizationKey.self) { value in
                            contentGroupOptions = value
                        }
                }
            }
            .trackingFrame(for: .scrollView)
            .ignoresSafeArea(
                edges: contentGroupOptions.contains(.ignoreSafeAreaTop) ? [.horizontal, .top] : .horizontal
            )
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.background.refresh()
            }
            #if os(tvOS)
            .onAppear {
                resolveFirstGroupFocus(using: proxy)
                resolveHomeReturn()
            }
            .onPreferenceChange(HomeFocusRowsKey.self) { rows in
                homeFocusRows = rows
                resolveHomeReturn()
            }
            .onChange(of: focusCoordinator.homeReturnTarget) { _, tile in
                if let tile {
                    proxy.scrollTo(tile.groupID, anchor: .center)
                }
            }
            .onChange(of: router.isRootOfPath) { _, isRoot in
                if isRoot {
                    resolveHomeReturn()
                }
            }
            .onChange(of: pendingFirstGroupFocus) {
                resolveFirstGroupFocus(using: proxy)
            }
            .onChange(of: viewModel.groups.count) { _, _ in
                resolveFirstGroupFocus(using: proxy)
            }
            #else
            .onReceive(tabItemSelected) { event in
                    if event.isRepeat, event.isRoot {
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            #endif
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        L10n.noResults.localizedCapitalized,
                        systemImage: "rectangle.on.rectangle.slash"
                    )
                    .focusable()
                } else {
                    contentView
                }
            case .error:
                viewModel.error.map(ErrorView.init)
            case .initial, .refreshing:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        #if os(tvOS)
            .environment(\.homeTileCoordinator, isHome ? focusCoordinator : nil)
            .environment(\.homeFocusRevision, focusCoordinator.homeRevision)
            .onAppear {
                if isHome, let navigationCoordinator = router.router.navigationCoordinator {
                    registerHomeFocus?(focusCoordinator, navigationCoordinator)
                }
            }
            .onReceive(Notifications[.didSendStopReport].publisher.receive(on: DispatchQueue.main)) {
                if isHome {
                    focusCoordinator.homeStopReported()
                }
            }
            .onChange(of: viewModel.background.is(.refreshing)) { wasRefreshing, refreshing in
                if isHome, wasRefreshing, !refreshing {
                    if viewModel.groups.isEmpty {
                        focusCoordinator.cancelHomeReturn()
                    } else {
                        focusCoordinator.homeRefreshFinished()
                    }
                }
            }
            .onChange(of: focusCoordinator.defersHomeRefresh) { _, deferred in
                if isHome {
                    viewModel.setDefersHomeRefresh(deferred)
                }
            }
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    pendingFirstGroupFocus = true
                }
            }
        #endif
            .navigationTitle(viewModel.provider.displayTitle)
        #if os(iOS)
            .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #elseif os(tvOS)
            .toolbar(router.isRootOfPath ? .hidden : .automatic, for: .navigationBar)
        #endif
            .onFirstAppear {
                viewModel.refresh()
            }
            .refreshable {
                viewModel.refresh()
            }
            .sinceLastDisappear { interval in
                viewModel.refreshIfNeeded(sinceLastDisappear: interval)
            }
            .onSceneWillEnterForeground {
                viewModel.refreshIfPendingChanges()
            }
            .topBarTrailing {
                if #unavailable(iOS 26.0) {
                    if viewModel.background.is(.refreshing) {
                        ProgressView()
                    }
                }
            }
            .environmentObject(focusCoordinator)
    }
}
