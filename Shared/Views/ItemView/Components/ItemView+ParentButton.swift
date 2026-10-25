//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct ParentButton: View {

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @Router
        private var router

        let title: String
        let id: String
        var episodeRouteItem: BaseItemDto?
        var episodeRouteOrigin: EpisodeRouteIntent.Origin?

        var body: some View {
            Button {
                #if os(tvOS)
                if let episodeRouteItem {
                    router.route(to: .resolvedEpisode(
                        item: episodeRouteItem,
                        origin: episodeRouteOrigin
                    ))
                    return
                }
                #endif
                router.route(to: .item(id: id))
            } label: {
                Label {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "chevron.forward")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .fontWeight(.semibold)
            }
            .foregroundStyle(.primary, .secondary)
            .labelStyle(
                CapsuleLabelStyle(
                    isIconTrailing: true
                )
            )
            #if os(tvOS)
            .buttonBorderShape(.roundedRectangle(radius: 0))
            #else
            .buttonBorderShape(.capsule)
            #endif
            .buttonStyle(.card)
            #if os(tvOS)
                .focusable(!isEpisodeRouteFocusPending)
            #endif
        }

        #if os(tvOS)
        private var isEpisodeRouteFocusPending: Bool {
            focusCoordinator.request?.hasPrefix("episode-artwork:") == true
        }
        #endif
    }
}
