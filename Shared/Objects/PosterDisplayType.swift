//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

#if os(iOS)
private let landscapeMaxWidth: CGFloat = 300
private let portraitMaxWidth: CGFloat = 200
#else
// The tvOS poster rows display five landscape or seven portrait columns.
// Leave a small allowance for focus scaling without requesting 500-point
// images for cards that render substantially smaller.
private let landscapeMaxWidth: CGFloat = 360
private let portraitMaxWidth: CGFloat = 240
#endif

enum PosterDisplayType: String, CaseIterable, Displayable, Storable, SystemImageable {

    enum Size: Equatable, Hashable, Storable {

        case extraSmall
        case small
        case medium
        case custom(width: CGFloat)

        var quality: Int? {
            90
        }

        func width(for displayType: PosterDisplayType) -> CGFloat? {
            switch self {
            case .extraSmall:
                switch displayType {
                case .landscape:
                    110
                case .portrait, .square:
                    60
                }
            case .small:
                switch displayType {
                case .landscape:
                    landscapeMaxWidth
                case .portrait, .square:
                    portraitMaxWidth
                }
            case .medium:
                landscapeMaxWidth
            case let .custom(width):
                width
            }
        }
    }

    case landscape
    case portrait
    case square

    var displayTitle: String {
        switch self {
        case .landscape:
            L10n.landscape
        case .portrait:
            L10n.portrait
        case .square:
            L10n.square
        }
    }

    var systemImage: String {
        switch self {
        case .landscape:
            "rectangle.fill"
        case .portrait:
            "rectangle.portrait.fill"
        case .square:
            "square.fill"
        }
    }
}
