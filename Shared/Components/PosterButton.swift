//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct PosterButton<Item: Poster>: View {

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    @Environment(\.viewContext)
    private var viewContext

    @Namespace
    private var namespace

    #if os(tvOS)
    @FocusState
    private var isFocused: Bool
    #endif

    @State
    private var posterSize: CGSize = .zero

    let item: Item
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Namespace.ID) -> Void

    init(
        item: Item,
        displayType: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        action: @escaping (Namespace.ID) -> Void
    ) {
        self.item = item
        self.displayType = displayType
        self.size = size
        self.action = action
    }

    @ViewBuilder
    private var contextMenuPreview: some View {
        buttonLabel()
            .frame(width: posterSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect)
    }

    @ViewBuilder
    private func posterImage(overlay: some View) -> some View {
        PosterImage(
            item: item,
            type: displayType,
            size: size
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { overlay.posterStyle(displayType) }
        .contentShape(.contextMenuPreview, Rectangle())
        .matchedTransitionSource(id: "item", in: namespace)
        .subtleShadow()
        #if os(tvOS)
            .overlay {
                Rectangle()
                    .stroke(
                        Color.snowfinIceBlue.opacity(isFocused ? 0.95 : 0),
                        lineWidth: 3
                    )
            }
            .scaleEffect(isFocused ? 1.035 : 1)
            .shadow(
                color: isFocused ? Color.snowfinIceBlue.opacity(0.28) : .clear,
                radius: isFocused ? 16 : 0
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
        #else
            .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private func buttonLabel(overlay: some View = EmptyView()) -> some View {
        VStack(alignment: .leading) {
            posterImage(overlay: overlay)

            if posterConfiguration.showLabels {
                item.posterLabel
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        Button {
            action(namespace)
        } label: {
            // Layout required for tvOS focused offset label behavior
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 12) {
                posterImage(overlay: item.posterOverlay(for: displayType))

                if posterConfiguration.showLabels {
                    item.posterLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #else
            buttonLabel(overlay: item.posterOverlay(for: displayType))
                .trackingSize($posterSize)
            #endif
        }
        .environment(\.posterDisplayType, displayType)
        .foregroundStyle(.primary, .secondary)
        #if os(tvOS)
            .buttonStyle(SnowfinPosterButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: 0))
            .focused($isFocused)
            .focusedValue(\.focusedPoster, AnyPoster(item))
        #else
            .buttonStyle(.borderless)
        #endif
            .posterContextMenu(for: item) {
                contextMenuPreview
                    .withViewContext(viewContext)
            }
    }
}

#if os(tvOS)
private struct SnowfinPosterButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
