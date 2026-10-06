//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer.UIVideoPlayerContainerViewController.SupplementContainerView {

    #if os(tvOS)
    struct SupplementTitleButtonStyle: ButtonStyle {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.isSelected)
        private var isSelected

        @ViewBuilder
        func makeBody(configuration: Configuration) -> some View {
            if UIDevice.supportsLiquidGlass {
                glassBody(configuration)
            } else {
                legacyBody(configuration)
            }
        }

        private func baseLabel(_ configuration: Configuration) -> some View {
            configuration.label
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(minHeight: 56)
        }

        private func glassBody(_ configuration: Configuration) -> some View {
            baseLabel(configuration)
                .foregroundStyle(isFocused || isSelected ? accentColor.overlayColor : .white)
                .glassEffect(
                    .regular
                        .tint(isFocused || isSelected ? accentColor : nil)
                        .interactive(isFocused),
                    in: Capsule()
                )
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: isFocused ? accentColor.opacity(0.3) : .clear, radius: isFocused ? 14 : 0)
                .opacity(inactiveSelectedOpacity)
                .animation(.easeInOut(duration: 0.1), value: isFocused)
                .animation(.easeInOut(duration: 0.1), value: isSelected)
        }

        private func legacyBody(_ configuration: Configuration) -> some View {
            baseLabel(configuration)
                .foregroundStyle(isFocused || isSelected ? accentColor.overlayColor : .white)
                .background {
                    if isFocused {
                        Capsule()
                            .fill(accentColor)
                    } else if isSelected {
                        Capsule()
                            .fill(accentColor.opacity(0.34))
                    } else {
                        Capsule()
                            .fill(Material.ultraThinMaterial)
                            .background {
                                Capsule()
                                    .fill(.white.opacity(0.2))
                            }
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(isFocused ? accentColor.opacity(0.72) : .white.opacity(0.16), lineWidth: 1)
                }
                .clipShape(Capsule())
                .subtleShadow()
                .opacity(inactiveSelectedOpacity)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: isFocused ? accentColor.opacity(0.3) : .clear, radius: isFocused ? 14 : 0)
                .animation(.easeInOut(duration: 0.1), value: isFocused)
                .animation(.easeInOut(duration: 0.1), value: isSelected)
        }

        private var inactiveSelectedOpacity: Double {
            isSelected && !isFocused ? 0.72 : 1
        }
    }
    #else
    struct SupplementTitleButtonStyle: PrimitiveButtonStyle {

        @Environment(\.isEnabled)
        private var isEnabled
        @Environment(\.isSelected)
        private var isSelected

        @State
        private var isPressed = false

        @ViewBuilder
        func makeBody(configuration: Configuration) -> some View {
            if #available(iOS 26.0, *) {
                glassBody(configuration)
            } else {
                legacyBody(configuration)
            }
        }

        private func baseLabel(_ configuration: Configuration) -> some View {
            configuration.label
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(minHeight: 36)
        }

        private func legacyBody(_ configuration: Configuration) -> some View {
            pressableBody(
                baseLabel(configuration)
                    .foregroundStyle(isSelected ? .black : .white)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.white)
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                    .subtleShadow(),
                configuration: configuration
            )
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(.bouncy(duration: 0.4), value: isPressed)
        }

        @available(iOS 26.0, *)
        private func glassBody(_ configuration: Configuration) -> some View {
            pressableBody(
                baseLabel(configuration)
                    .foregroundStyle(isSelected ? .black : .white)
                    .glassEffect(
                        .regular
                            .tint(isSelected ? .white : nil),
                        in: Capsule()
                    ),
                configuration: configuration
            )
        }

        private func pressableBody(
            _ content: some View,
            configuration: Configuration
        ) -> some View {
            content
                .contentShape(Capsule())
                .onTapGesture {
                    configuration.trigger()
                }
                .onLongPressGesture(minimumDuration: 0.01) {} onPressingChanged: { newValue in
                    if !newValue, isPressed, isEnabled {
                        UIDevice.impact(.light)
                    }

                    isPressed = newValue
                }
                .opacity(isPressed ? 0.6 : 1)
                .animation(.easeInOut(duration: 0.1), value: isSelected)
        }
    }
    #endif
}
