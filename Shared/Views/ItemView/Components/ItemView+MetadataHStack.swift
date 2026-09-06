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

    struct MetadataHStack: View {

        let item: BaseItemDto

        var body: some View {
            DotHStack {
                #if os(tvOS)
                if let premiereYear = item.premiereDateYear {
                    Text(premiereYear)
                }

                if let firstGenre = item.genres?.first {
                    Text(firstGenre)
                }

                if let seasonEpisodeLabel = item.seasonEpisodeLabel {
                    Text(seasonEpisodeLabel)
                }

                if let runtime = item.runtime {
                    Text(runtime, format: .hourMinuteAbbreviated)
                }

                if let officialRating = item.officialRating, officialRating.isNotEmpty {
                    Text(officialRating)
                }
                #else
                if let firstGenre = item.genres?.first {
                    Text(firstGenre)
                }

                if let premiereYear = item.premiereDateYear {
                    Text(premiereYear)
                }

                if let runtime = item.runtime {
                    Text(runtime, format: .hourMinuteAbbreviated)
                }

                if let seasonEpisodeLabel = item.seasonEpisodeLabel {
                    Text(seasonEpisodeLabel)
                }
                #endif
            }
            .font(UIDevice.isTV ? .callout : .caption)
            .fontWeight(.semibold)
            #if os(tvOS)
                .foregroundStyle(.white.opacity(0.78))
            #else
                .foregroundStyle(.secondary)
            #endif
        }
    }
}
