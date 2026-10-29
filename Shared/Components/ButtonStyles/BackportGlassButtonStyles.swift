//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension BackportButtonStyle where Self == BackportGlassButtonStyle {

    static var glass: Self {
        BackportGlassButtonStyle()
    }
}

extension BackportButtonStyle where Self == BackportGlassProminentButtonStyle {

    static var glassProminent: Self {
        BackportGlassProminentButtonStyle()
    }
}

struct BackportGlassButtonStyle: BackportButtonStyle {

    private var legacyGlass = BackportGlass.regular

    func shadow(_ isEnabled: Bool = true) -> Self {
        var copy = self
        copy.legacyGlass = legacyGlass.shadow(isEnabled)
        return copy
    }

    func makeBody(configuration: Configuration) -> some View {
        BackportGlassButtonStyleBody(
            configuration: configuration,
            legacyGlass: legacyGlass,
            prominence: .standard
        )
    }
}

struct BackportGlassProminentButtonStyle: BackportButtonStyle {

    private var legacyGlass = BackportGlass.regular

    func shadow(_ isEnabled: Bool = true) -> Self {
        var copy = self
        copy.legacyGlass = legacyGlass.shadow(isEnabled)
        return copy
    }

    func makeBody(configuration: Configuration) -> some View {
        BackportGlassButtonStyleBody(
            configuration: configuration,
            legacyGlass: legacyGlass,
            prominence: .prominent
        )
    }
}

private struct BackportGlassButtonStyleBody: View {

    enum Prominence {
        case standard
        case prominent
    }

    @Environment(\.controlSize)
    private var controlSize

    @Environment(\.isEnabled)
    private var isEnabled

    @Environment(\.screenTheme)
    private var screenTheme

    let configuration: PrimitiveButtonStyleConfiguration
    let legacyGlass: BackportGlass
    let prominence: Prominence

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), UIDevice.supportsLiquidGlass {
            nativeBody
        } else {
            fallbackBody
        }
    }

    @available(iOS 26.0, tvOS 26.0, *)
    @ViewBuilder
    private var nativeBody: some View {
        switch prominence {
        case .standard:
            nativeButton
                .buttonStyle(.glass)
        case .prominent:
            #if os(tvOS)
            nativeButton
                .buttonStyle(.glassProminent)
                .tint(prominentTint)
                .foregroundStyle(prominentForeground)
            #else
            nativeButton
                .buttonStyle(.glassProminent)
            #endif
        }
    }

    private var nativeButton: some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
        }
        #if os(tvOS)
        .buttonBorderShape(.roundedRectangle(radius: 0))
        #endif
    }

    @ViewBuilder
    private var fallbackBody: some View {
        switch prominence {
        case .standard:
            fallbackButton
                .backport
                #if os(tvOS)
                .glassEffect(legacyGlass, in: .rect)
                #else
                .glassEffect(legacyGlass, in: .capsule)
                #endif
        case .prominent:
            fallbackButton
                .backport
                #if os(tvOS)
                .glassEffect(
                    legacyGlass.selection(
                        tint: prominentTint,
                        foregroundColor: prominentForeground,
                        disabledTint: prominentDisabledTint,
                        disabledForegroundColor: prominentDisabledForeground
                    ),
                    in: .rect
                )
                #else
                .glassEffect(
                    legacyGlass.selection(
                        tint: prominentTint,
                        foregroundColor: prominentTint.overlayColor
                    ),
                    in: .capsule
                )
                #endif
        }
    }

    @ViewBuilder
    private var fallbackButton: some View {
        let button = Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            fallbackLabel
                .padding(fallbackPadding)
        }

        #if os(tvOS)
        button
        #else
        button.buttonStyle(.borderless)
        #endif
    }

    @ViewBuilder
    private var fallbackLabel: some View {
        if isEnabled {
            configuration.label
        } else {
            configuration.label
                .foregroundStyle(.tertiary)
        }
    }

    private var fallbackPadding: EdgeInsets {
        switch controlSize {
        case .mini:
            EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        case .small:
            EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        case .regular:
            EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        case .large:
            EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        case .extraLarge:
            EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        @unknown default:
            EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        }
    }

    private var prominentTint: Color {
        switch configuration.role {
        case .destructive, .cancel:
            .red
        default:
            #if os(tvOS)
            isEnabled ? screenTheme.actions.primaryFill.swiftUIColor : screenTheme.actions.primaryDisabledFill.swiftUIColor
            #else
            .accentColor
            #endif
        }
    }

    private var prominentForeground: Color {
        switch configuration.role {
        case .destructive, .cancel:
            prominentTint.overlayColor
        default:
            #if os(tvOS)
            isEnabled ? screenTheme.actions.primaryForeground.swiftUIColor : screenTheme.actions.primaryDisabledForeground.swiftUIColor
            #else
            prominentTint.overlayColor
            #endif
        }
    }

    private var prominentDisabledTint: Color? {
        #if os(tvOS)
        switch configuration.role {
        case .destructive, .cancel:
            nil
        default:
            screenTheme.actions.primaryDisabledFill.swiftUIColor
        }
        #else
        nil
        #endif
    }

    private var prominentDisabledForeground: Color? {
        #if os(tvOS)
        switch configuration.role {
        case .destructive, .cancel:
            nil
        default:
            screenTheme.actions.primaryDisabledForeground.swiftUIColor
        }
        #else
        nil
        #endif
    }
}
