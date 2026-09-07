//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct SearchView: View {

    #if os(iOS)
    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters
    #endif

    #if os(iOS)
    @FocusState
    private var isSearchFocused: Bool
    #endif

    #if os(tvOS)
    @FocusState
    private var focusedSuggestionID: String?

    @EnvironmentObject
    private var searchFocus: TVSearchFocusCoordinator
    #endif

    @State
    private var searchQuery = ""

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel = SearchViewModel()

    @TabItemSelected
    private var tabItemSelected

    @ViewBuilder
    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(viewModel.suggestions) { item in
                Button(item.displayTitle) {
                    searchQuery = item.displayTitle
                }
                #if os(tvOS)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focused(
                    $focusedSuggestionID,
                    equals: item.id ?? item.displayTitle
                )
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .edgePadding()
        .focusSection()
    }

    #if os(tvOS)
    private func focusSearchContent() {
        searchFocus.cancelEntry()

        if viewModel.canSearch,
           let firstGroup = viewModel.itemContentGroupViewModel.groups.first
        {
            focusCoordinator.focus(firstGroup.id)
        } else if let firstSuggestion = viewModel.suggestions.first {
            focusedSuggestionID = firstSuggestion.id ?? firstSuggestion.displayTitle
        }
    }
    #endif

    @ViewBuilder
    private var resultsView: some View {
        ScrollView {
            ContentGroupVStack(
                groups: viewModel.itemContentGroupViewModel.groups
            )
            .edgePadding(.vertical)
        }
        .scrollIndicators(.hidden)
        .focusSection()
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .error:
                viewModel.error.map(ErrorView.init)
            case .initial:
                if viewModel.canSearch {
                    if viewModel.isEmpty {
                        Text(L10n.noResults)
                    } else {
                        resultsView
                    }
                } else {
                    suggestionsView
                }
            case .searching:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(L10n.search)
        .toolbarTitleDisplayMode(.inline)
        #if os(tvOS)
            .tvSearchFocusRegistration(searchFocus)
            .onReceive(searchFocus.$entryRequest) { _ in
                focusedSuggestionID = nil
                focusCoordinator.clearRequest()
            }
        #else
            .searchFocused($isSearchFocused)
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    isSearchFocused = true
                }
            }
        #endif
            .onFirstAppear {
                    viewModel.getSuggestions()
                }
                .onChange(of: searchQuery) {
                    viewModel.search(query: searchQuery)
                }
                .searchable(
                    text: $searchQuery,
                    prompt: L10n.search
                )
                .environmentObject(focusCoordinator)
        #if os(tvOS)
            .edgePadding(.top)
            .focusSection()
            .onMoveCommand { direction in
                if direction == .down, searchFocus.isFieldFocused {
                    focusSearchContent()
                }
            }
        #else
            .navigationBarFilterDrawer(
                viewModel: viewModel.filterViewModel,
                types: enabledDrawerFilters
            )
        #endif
    }
}
