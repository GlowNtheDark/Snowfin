//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(tvOS)
struct BasicHoverButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(
                        Color.snowfinIceBlue.opacity(isFocused ? 0.9 : 0),
                        lineWidth: 2
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : isFocused ? 1.035 : 1)
            .shadow(
                color: isFocused ? Color.snowfinIceBlue.opacity(0.28) : .clear,
                radius: isFocused ? 16 : 0
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#else
typealias BasicHoverButtonStyle = BorderlessButtonStyle
#endif
