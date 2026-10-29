//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct ThemePreference: Equatable, Sendable {

    let identifier: ThemeIdentifier
    let customPrimary: ThemeColor?

    var palette: ThemePalette {
        ThemeResolver.resolve(identifier, customPrimary: customPrimary)
    }

    var compatibilityAccent: ThemeColor {
        if identifier == .custom {
            customPrimary ?? ThemeResolver.resolve(.arctic).seed
        } else {
            palette.seed
        }
    }

    static let arctic = ThemePreference(identifier: .arctic, customPrimary: nil)

    static func custom(primary: ThemeColor) -> ThemePreference {
        ThemePreference(identifier: .custom, customPrimary: primary)
    }

    static var applicationDefault: ThemePreference {
        #if os(tvOS)
        .arctic
        #else
        .custom(primary: ThemeColor(hex: 0xAC5CC3))
        #endif
    }
}

enum ThemePreferenceMigration {

    static let currentVersion = 1

    static func resolve(
        existing: ThemePreference?,
        migrationVersion: Int,
        legacyAccent: ThemeColor
    ) -> ThemePreference {
        if let existing {
            return existing
        }
        guard migrationVersion < currentVersion else { return .applicationDefault }

        if legacyAccent == ThemeColor(hex: 0x2EA8FF) {
            return .arctic
        }

        return .custom(primary: legacyAccent)
    }
}
