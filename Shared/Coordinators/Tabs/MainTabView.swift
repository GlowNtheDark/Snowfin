//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    @StateObject
    private var tabCoordinator: TabCoordinator

    #if os(tvOS)
    @Namespace
    private var sidebarFocusNamespace

    @FocusState
    private var focusedSidebarTabID: String?

    @State
    private var previewedSidebarTabID: String?

    @State
    private var hasRequestedLaunchContentFocus = false

    @StateObject
    private var searchFocus = TVSearchFocusCoordinator()

    @Default(.accentColor)
    private var accentColor
    #endif

    init() {
        _tabCoordinator = StateObject(wrappedValue: Self.defaultTabCoordinator)
    }

    private static var defaultTabCoordinator: TabCoordinator {
        #if os(iOS)
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.search
            TabItem.media
        }
        #else
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.library(
                title: L10n.tvShowsCapitalized,
                systemName: "tv",
                filters: .init(itemTypes: [.series])
            )
            TabItem.library(
                title: L10n.movies,
                systemName: "film",
                filters: .init(itemTypes: [.movie])
            )
            TabItem.search
            TabItem.media
            TabItem.settings
        }
        #endif
    }

    private func routePendingDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        Task { @MainActor in
            let route = deepLink.route()
            await tabCoordinator.route(to: route)
        }
    }

    #if os(iOS)
    private func tabContent() -> some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                Tab(
                    value: tab.item.id,
                    role: tab.item.id == TabItem.search.id ? .search : nil
                ) {
                    NavigationInjectionView(
                        coordinator: tab.coordinator
                    ) {
                        tab.item.content
                            .if(tabCoordinator.tabs.first?.item.id == tab.item.id) { view in
                                view.topBarTrailing {
                                    FirstTabSettingsBarButton()
                                }
                            }
                    }
                    .environmentObject(tabCoordinator)
                    .environment(\.tabItemSelected, tab.publisher)
                } label: {
                    Label(
                        tab.item.displayTitle,
                        systemImage: tab.item.systemImage
                    )
                    .symbolRenderingMode(.monochrome)
                }
            }
        }
    }
    #else
    private var isSidebarExpanded: Bool {
        focusedSidebarTabID != nil
    }

    private var displayedTabID: String? {
        previewedSidebarTabID ?? tabCoordinator.selectedTabID
    }

    private func activateSidebarTab(_ tab: TabCoordinator.TabData) {
        previewedSidebarTabID = tab.item.id
        if tabCoordinator.selectedTabID != tab.item.id {
            tabCoordinator.selectedTabID = tab.item.id
        }
        focusedSidebarTabID = nil

        if tab.item.id == TabItem.search.id, tab.coordinator.path.isEmpty {
            searchFocus.requestEntry()
            return
        }

        // Let the sidebar relinquish focus before delivering the repeated-tab
        // event that asks the destination to focus its primary content.
        DispatchQueue.main.async {
            guard displayedTabID == tab.item.id else { return }
            tab.publisher.send(.init(isRoot: tab.coordinator.path.isEmpty, isRepeat: true))
        }
    }

    private func returnToSidebar(tabID: String) {
        guard tabCoordinator.tabs.contains(where: { $0.item.id == tabID }) else { return }
        focusedSidebarTabID = tabID
    }

    private func requestInitialHomeContentFocus(for tab: TabCoordinator.TabData) {
        guard !hasRequestedLaunchContentFocus,
              tab.item.id == tabCoordinator.tabs.first?.item.id,
              tab.item.id == tabCoordinator.selectedTabID,
              tab.coordinator.path.isEmpty
        else { return }

        hasRequestedLaunchContentFocus = true
        activateSidebarTab(tab)
    }

    @ViewBuilder
    private func selectedTabContent() -> some View {
        if let tab = tabCoordinator.tabs.first(where: { $0.item.id == displayedTabID }) {
            NavigationInjectionView(
                coordinator: tab.coordinator
            ) {
                tab.item.content
            }
            .environmentObject(tabCoordinator)
            .environment(\.tabItemSelected, tab.publisher)
            .id(tab.item.id)
            .environment(\.initialTabCandidateReady) {
                requestInitialHomeContentFocus(for: tab)
            }
            .onExitCommand {
                returnToSidebar(tabID: tab.item.id)
            }
        }
    }

    private func sidebarButton(for tab: TabCoordinator.TabData) -> some View {
        let isSelected = tab.item.id == displayedTabID
        let isFocused = tab.item.id == focusedSidebarTabID

        return Button {
            activateSidebarTab(tab)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: tab.item.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 38, height: 38)

                if isSidebarExpanded {
                    Text(tab.item.displayTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, isSidebarExpanded ? 14 : 11)
            .frame(width: isSidebarExpanded ? nil : 60, alignment: .leading)
            .frame(minHeight: 64, alignment: .leading)
            .frame(maxWidth: isSidebarExpanded ? .infinity : nil, alignment: .leading)
            .background {
                if isFocused {
                    Rectangle()
                        .fill(accentColor)
                } else if isSelected {
                    Rectangle()
                        .fill(accentColor.opacity(0.22))
                        .overlay {
                            Rectangle()
                                .stroke(accentColor.opacity(0.8), lineWidth: 2)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SnowfinSidebarButtonStyle())
        .focused($focusedSidebarTabID, equals: tab.item.id)
        .onMoveCommand { direction in
            guard direction == .right else { return }
            activateSidebarTab(tab)
        }
        .prefersDefaultFocus(isSelected, in: sidebarFocusNamespace)
        .accessibilityLabel(tab.item.displayTitle)
        .padding(.horizontal, 8)
    }

    private func tabContent() -> some View {
        ZStack(alignment: .leading) {
            selectedTabContent()
                .padding(.leading, 84)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image("screen-tvOS-mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)

                    if isSidebarExpanded {
                        Text(L10n.applicationBrand)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(height: 66)
                .padding(.horizontal, 14)

                ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                    sidebarButton(for: tab)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 60)
            .padding(.bottom, 30)
            .frame(width: isSidebarExpanded ? 292 : 84)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                Rectangle()
                    .fill(Color.black)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.snowfinIceBlue.opacity(0.2))
                            .frame(width: 1)
                    }
            }
            .focusScope(sidebarFocusNamespace)
            .focusSection()
            .clipped()
            // Expand the complete rail, including its background and clipping bounds.
            .ignoresSafeArea(.container, edges: [.horizontal, .vertical])
            .zIndex(1)
            .onChange(of: focusedSidebarTabID) { previousTabID, tabID in
                guard let tabID,
                      tabCoordinator.tabs.contains(where: { $0.item.id == tabID })
                else { return }

                // Directional entry chooses the nearest row, not the active tab.
                // Correct only entry from content; up/down within the menu previews normally.
                if previousTabID == nil,
                   let activeTabID = tabCoordinator.selectedTabID,
                   activeTabID != tabID
                {
                    focusedSidebarTabID = activeTabID
                    return
                }

                previewedSidebarTabID = tabID
            }
        }
        .background(Color.snowfinDeepNavy)
        .onChange(of: tabCoordinator.selectedTabID) { _, tabID in
            guard focusedSidebarTabID == nil else { return }
            previewedSidebarTabID = tabID
        }
        .transaction(value: isSidebarExpanded) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
    #endif

    var body: some View {
        tabContent()
            .onChange(of: userSessionManager.pendingDeepLink) {
                routePendingDeepLink(userSessionManager.consumePendingDeepLink())
            }
            .onReceive(userSessionManager.routePublisher) { route in
                Task { @MainActor in
                    await tabCoordinator.route(to: route)
                }
            }
        #if os(tvOS)
            .environmentObject(searchFocus)
            .background(alignment: .top) {
                FocusedPosterCinematicBackgroundView()
            }
        #endif
    }
}

#if os(tvOS)
extension EnvironmentValues {
    @Entry
    var initialTabCandidateReady: (() -> Void)? = nil
}

private struct SnowfinSidebarButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

#if os(iOS)
private struct FirstTabSettingsBarButton: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    var body: some View {
        if router.isRootOfPath,
           let userSession
        {
            SettingsBarButton(
                server: userSession.server,
                user: userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }
}
#endif
