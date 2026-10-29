//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import Defaults
import SwiftUI

struct ThemeSettingsView: View {

    @Default(.userThemeIdentifier)
    private var storedThemeIdentifier

    @Default(.userThemeCustomPrimaryColor)
    private var customPrimaryColor

    @State
    private var initialFocusTheme = ThemeIdentifier(rawValue: Defaults[.userThemeIdentifier]) ?? .arctic

    @FocusState
    private var focusedTheme: ThemeIdentifier?

    @Router
    private var router

    private var selectedTheme: ThemeIdentifier {
        ThemeIdentifier(rawValue: storedThemeIdentifier) ?? .arctic
    }

    private var customPalette: ThemePalette {
        ThemeResolver.resolve(.custom, customPrimary: ThemeColor(customPrimaryColor))
    }

    var body: some View {
        Form(systemImage: "paintpalette.fill") {
            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20),
                    ],
                    spacing: 20
                ) {
                    ForEach(ThemeIdentifier.allCases, id: \.self) { identifier in
                        ThemePreviewCard(
                            identifier: identifier,
                            palette: palette(for: identifier),
                            isSelected: selectedTheme == identifier,
                            focusedTheme: $focusedTheme
                        ) {
                            select(identifier)
                        }
                    }
                }
                .padding(.vertical, 12)
                .focusSection()
            } header: {
                Text(L10n.theme)
            } footer: {
                Text(L10n.themeSelectionDescription)
            }
        }
        .navigationTitle(L10n.theme)
        .defaultFocus($focusedTheme, initialFocusTheme, priority: .userInitiated)
    }

    private func palette(for identifier: ThemeIdentifier) -> ThemePalette {
        if identifier == .custom {
            customPalette
        } else {
            ThemeResolver.resolve(identifier)
        }
    }

    private func select(_ identifier: ThemeIdentifier) {
        guard identifier != .custom else {
            router.route(to: .customThemeEditor)
            return
        }

        // Keep the saved Custom seed intact while a curated theme is active.
        Defaults[.userThemeIdentifier] = identifier.rawValue
        Defaults[.userThemePreferenceMigrationVersion] = ThemePreferenceMigration.currentVersion
    }
}

struct CustomThemeEditorView: View {

    @State
    private var draftPrimaryColor: Color

    @Router
    private var router

    init() {
        _draftPrimaryColor = State(initialValue: Defaults[.userThemeCustomPrimaryColor])
    }

    private var draftPalette: ThemePalette {
        ThemeResolver.resolve(.custom, customPrimary: ThemeColor(draftPrimaryColor))
    }

    var body: some View {
        Form(systemImage: "paintpalette.fill") {
            Section {
                ColorPicker(
                    L10n.primaryColor,
                    selection: $draftPrimaryColor,
                    supportsOpacity: false
                )
            } footer: {
                Text(L10n.themeCustomDescription)
            }

            Section(L10n.preview) {
                ThemePalettePreview(palette: draftPalette)
                    .padding(.vertical, 8)
            }

            Section {
                Button(L10n.save, action: save)
                Button(L10n.cancel) {
                    router.dismiss()
                }
            }
        }
        .navigationTitle(L10n.custom)
    }

    private func save() {
        // Persist the original Color value; the resolver only converts it for preview.
        Defaults[.userThemeCustomPrimaryColor] = draftPrimaryColor
        Defaults[.userThemeIdentifier] = ThemeIdentifier.custom.rawValue
        Defaults[.userThemePreferenceMigrationVersion] = ThemePreferenceMigration.currentVersion
        router.dismiss()
    }
}

private struct ThemePreviewCard: View {

    let identifier: ThemeIdentifier
    let palette: ThemePalette
    let isSelected: Bool
    let focusedTheme: FocusState<ThemeIdentifier?>.Binding
    let action: () -> Void

    private var isFocused: Bool {
        focusedTheme.wrappedValue == identifier
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(identifier.displayName)
                        .font(.headline)
                        .foregroundStyle(palette.foregrounds.primary.swiftUIColor)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.selection.indicator.swiftUIColor)
                    }
                }

                ThemePalettePreview(palette: palette)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
                isSelected ? palette.selection.background.swiftUIColor : palette.surfaces.elevated.swiftUIColor,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .shadow(
                color: isFocused ? palette.focus.glow.swiftUIColor.opacity(palette.focus.glowOpacity) : .clear,
                radius: isFocused ? min(palette.focus.glowRadius, 12) : 0
            )
        }
        .buttonStyle(.plain)
        .focused(focusedTheme, equals: identifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(identifier.displayName))
        .accessibilityValue(Text(isSelected ? L10n.selected : ""))
    }

    private var borderColor: Color {
        if isFocused {
            palette.focus.keylineOnSurface.swiftUIColor
        } else if isSelected {
            palette.selection.indicator.swiftUIColor
        } else {
            .clear
        }
    }

    private var borderWidth: CGFloat {
        if isFocused {
            4
        } else if isSelected {
            2
        } else {
            0
        }
    }
}

private struct ThemePalettePreview: View {

    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.surfaces.elevated.swiftUIColor)
                    .frame(height: 22)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.surfaces.elevatedHigh.swiftUIColor)
                    .frame(height: 22)
            }

            HStack(spacing: 8) {
                actionPreview(
                    L10n.play,
                    fill: palette.actions.primaryFill,
                    foreground: palette.actions.primaryForeground,
                    outline: palette.focus.keylineOnPrimaryFill
                )

                actionPreview(
                    L10n.details,
                    fill: palette.actions.secondaryFill,
                    foreground: palette.actions.secondaryForeground,
                    outline: palette.actions.secondaryBoundary
                )
            }

            HStack(spacing: 6) {
                Text(L10n.primary)
                    .foregroundStyle(palette.foregrounds.primary.swiftUIColor)
                Text(L10n.preview)
                    .foregroundStyle(palette.foregrounds.secondary.swiftUIColor)
                Spacer(minLength: 0)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surfaces.canvas.swiftUIColor,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func actionPreview(
        _ title: String,
        fill: ThemeColor,
        foreground: ThemeColor,
        outline: ThemeColor
    ) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground.swiftUIColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(fill.swiftUIColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(outline.swiftUIColor, lineWidth: 2)
            }
    }
}

extension ThemeIdentifier {
    var displayName: String {
        switch self {
        case .arctic, .amethyst, .ember, .evergreen:
            rawValue.capitalized
        case .custom:
            L10n.custom
        }
    }
}
#endif
