//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct CinematicItemSelector<Item: Poster, TopContent: View>: View {

    @FocusState
    private var isSectionFocused

    @FocusedValue(\.focusedPoster)
    private var focusedPoster

    @State
    private var selectedPoster: AnyPoster?

    private let action: (Item) -> Void
    private let items: [Item]
    private let topContent: (Item) -> TopContent

    init(
        items: [Item],
        action: @escaping (Item) -> Void,
        @ViewBuilder topContent: @escaping (Item) -> TopContent
    ) {
        self.items = items
        self.action = action
        self.topContent = topContent
    }

    private var resolvedSelectedPoster: AnyPoster? {
        selectedPoster ?? items.first.map { AnyPoster($0) }
    }

    private var selectedItem: Item? {
        resolvedSelectedPoster?._poster as? Item
    }

    private func updateSelectedPoster() {
        guard isSectionFocused, let focusedPoster else { return }
        selectedPoster = focusedPoster
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            if let selectedItem {
                topContent(selectedItem)
                    .id(selectedItem.hashValue)
                    .transition(.opacity)
            }

            PosterHStack(
                elements: items,
                displayType: .portrait,
                size: .small
            ) { item, _ in
                action(item)
            }
            .environment(\.launchFocusFirstPoster, items.first.map { AnyPoster($0) })
        }
        .background(Color.snowfinDeepNavy)
        .onChange(of: focusedPoster) {
            updateSelectedPoster()
        }
        .onChange(of: isSectionFocused) {
            updateSelectedPoster()
        }
        .focusSection()
        .focused($isSectionFocused)
    }
}

extension CinematicItemSelector where TopContent == EmptyView {

    init(
        items: [Item],
        action: @escaping (Item) -> Void = { _ in }
    ) {
        self.init(
            items: items,
            action: action
        ) { _ in
            EmptyView()
        }
    }
}
