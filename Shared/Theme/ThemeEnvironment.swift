//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension EnvironmentValues {
    @Entry
    var screenTheme: ThemePalette = ThemeResolver.resolve(ThemeResolver.defaultIdentifier)
}

extension ThemeColor {

    init(_ color: Color) {
        let components = color.rgbaComponents
        self.init(
            red: Double(components.red),
            green: Double(components.green),
            blue: Double(components.blue)
        )
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
