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
    private enum SearchFocusTarget: Hashable {
        case field
        case key(String)
    }

    @FocusState
    private var focusedSearchTarget: SearchFocusTarget?

    @EnvironmentObject
    private var searchFocus: TVSearchFocusCoordinator

    @Default(.accentColor)
    private var accentColor

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
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .edgePadding()
        .focusSection()
    }

    #if os(tvOS)
    private let characterStripKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)

    private func fulfillSearchEntry() {
        guard searchFocus.hasPendingEntry else { return }
        focusCoordinator.clearRequest()
        focusedSearchTarget = .field
    }

    private func focusSearchContent() {
        searchFocus.cancelEntry()
        focusedSearchTarget = nil

        if viewModel.canSearch,
           let firstGroup = viewModel.itemContentGroupViewModel.groups.first
        {
            focusCoordinator.focus(firstGroup.id)
        }
    }

    private func beginEditing() {
        focusedSearchTarget = .key(characterStripKeys[0])
    }

    private func appendSearchCharacter(_ character: String) {
        searchQuery.append(character.lowercased())
    }

    private func removeSearchCharacter() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            Text(searchQuery.isEmpty ? L10n.search : searchQuery)
                .foregroundStyle(searchQuery.isEmpty ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .font(.title3)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(.white.opacity(0.06))
        .overlay {
            Rectangle()
                .stroke(
                    focusedSearchTarget == .field ? accentColor.opacity(0.9) : .white.opacity(0.16),
                    lineWidth: focusedSearchTarget == .field ? 2 : 1
                )
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focusedSearchTarget, equals: .field)
        .edgePadding(.horizontal)
        .onTapGesture(perform: beginEditing)
        .onMoveCommand { direction in
            if direction == .down {
                focusSearchContent()
            }
        }
    }

    private var characterStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(characterStripKeys, id: \.self) { key in
                    characterKey(key)
                }

                characterKey("SPACE", label: "Space")
                characterKey("DELETE", systemImage: "delete.left")
                characterKey("CLEAR", label: "Clear")
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .edgePadding(.horizontal)
    }

    private func characterKey(
        _ key: String,
        label: String? = nil,
        systemImage: String? = nil
    ) -> some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else {
                Text(label ?? key)
            }
        }
        .font(.callout.weight(.medium))
        .frame(minWidth: label == "Space" ? 88 : 42, minHeight: 34)
        .background(.white.opacity(0.06))
        .overlay {
            Rectangle()
                .stroke(
                    focusedSearchTarget == .key(key) ? accentColor.opacity(0.9) : .white.opacity(0.12),
                    lineWidth: focusedSearchTarget == .key(key) ? 2 : 1
                )
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focusedSearchTarget, equals: .key(key))
        .onTapGesture {
            switch key {
            case "SPACE":
                appendSearchCharacter(" ")
            case "DELETE":
                removeSearchCharacter()
            case "CLEAR":
                searchQuery = ""
            default:
                appendSearchCharacter(key)
            }
        }
        .onMoveCommand { direction in
            if direction == .down {
                focusSearchContent()
            }
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

    private var searchContent: some View {
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
                if viewModel.isNotEmpty {
                    resultsView
                } else {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.2), value: viewModel.state)
    }

    @ViewBuilder
    private var searchSurface: some View {
        #if os(tvOS)
        VStack(spacing: 12) {
            searchField
            characterStrip

            searchContent
        }
        #else
        searchContent
        #endif
    }

    var body: some View {
        searchSurface
            .ignoresSafeArea(.keyboard)
            .navigationTitle(L10n.search)
            .toolbarTitleDisplayMode(.inline)
        #if os(tvOS)
            .onAppear {
                fulfillSearchEntry()
            }
            .onDisappear {
                searchFocus.cancelEntry()
            }
            .onReceive(searchFocus.$entryRequest) { _ in
                fulfillSearchEntry()
            }
            .onChange(of: focusedSearchTarget) {
                if focusedSearchTarget != nil {
                    searchFocus.cancelEntry()
                }
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
                .environmentObject(focusCoordinator)
        #if os(tvOS)
            .edgePadding(.top)
            .focusSection()
        #else
            .searchable(
                text: $searchQuery,
                prompt: L10n.search
            )
            .navigationBarFilterDrawer(
                viewModel: viewModel.filterViewModel,
                types: enabledDrawerFilters
            )
        #endif
    }
}
