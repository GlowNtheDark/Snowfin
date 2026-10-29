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

    @Environment(\.isEnabled)
    private var isEnabled

    @Environment(\.screenTheme)
    private var screenTheme

    var scalesOnInteraction = true
    var outlineInset: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        let isVisuallyFocused = isEnabled && isFocused
        let scale = isEnabled ? (configuration.isPressed ? 0.97 : isVisuallyFocused ? 1.035 : 1) : 1
        let focusKeyline = isVisuallyFocused ? screenTheme.focus.keylineOnSurface.swiftUIColor : .clear
        let focusGlow = isVisuallyFocused ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity) : .clear

        return configuration.label
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(
                        focusKeyline,
                        lineWidth: 2
                    )
                    .padding(outlineInset)
            }
            .scaleEffect(scalesOnInteraction ? scale : 1)
            .shadow(
                color: focusGlow,
                radius: isVisuallyFocused ? screenTheme.focus.glowRadius : 0
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#else
typealias BasicHoverButtonStyle = BorderlessButtonStyle
#endif
