//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Standalone checks for the pure Foundation resolver; the Xcode schemes have no test target.
// Run with: swiftc Shared/Theme/ThemePalette.swift Shared/Theme/ThemePreference.swift Tests/ThemeResolverTests.swift -o
// /tmp/theme-resolver-tests

import Foundation

@main
enum ThemeResolverTests {

    static func main() {
        testContrastFormula()
        testCuratedPalettes()
        testCustomExtremes()
        testCustomInputClamping()
        testLegacyPreferenceMigration()
        testPerUserPreferenceResolution()

        print("Theme resolver checks passed.")
    }

    private static func testContrastFormula() {
        let black = ThemeColor(hex: 0x000000)
        let white = ThemeColor(hex: 0xFFFFFF)
        let gray = ThemeColor(hex: 0x767676)

        expect(black.contrastRatio(against: white) == 21, "black/white contrast should be 21:1")
        expect(gray.contrastRatio(against: white) >= 4.5, "#767676 should meet 4.5:1 against white")
    }

    private static func testCuratedPalettes() {
        expect(ThemeResolver.defaultIdentifier == .arctic, "Arctic should be the intended default theme")

        for identifier in ThemeIdentifier.allCases where identifier != .custom {
            let palette = ThemeResolver.resolve(identifier)
            expect(palette.identifier == identifier, "resolver should retain the curated identifier")
            verify(palette, label: identifier.rawValue)
        }

        let arctic = ThemeResolver.resolve(.arctic)
        expect(arctic.seed.hex == 0x2EA8FF, "Arctic should retain Screen Ice Blue")
        expect(arctic.surfaces.canvas.hex == 0x010305, "Arctic should retain Screen Deep Navy")
        expect(arctic.actions.primaryFill.hex == arctic.seed.hex, "Arctic primary action should retain Screen Ice Blue")
        expect(arctic == ThemeResolver.resolve(.arctic), "curated resolution should be deterministic")

        let customFallback = ThemeResolver.resolve(.custom)
        expect(customFallback.seed == arctic.seed, "Custom without a seed should resolve deterministically to Arctic")
        verify(customFallback, label: "custom fallback")
    }

    private static func testCustomExtremes() {
        let cases: [(String, UInt32)] = [
            ("near-black", 0x010101),
            ("black", 0x000000),
            ("white", 0xFFFFFF),
            ("yellow", 0xFFFF00),
            ("saturated red", 0xFF0000),
            ("saturated magenta", 0xFF00FF),
            ("saturated cyan", 0x00FFFF)
        ]

        for (label, hex) in cases {
            let seed = ThemeColor(hex: hex)
            let palette = ThemeResolver.resolve(.custom, customPrimary: seed)

            expect(palette.seed == seed, "custom palette should preserve the original seed for \(label)")
            verify(palette, label: label)
        }

        let blackPalette = ThemeResolver.resolve(.custom, customPrimary: ThemeColor(hex: 0x000000))
        expect(
            blackPalette.actions.primaryFill != blackPalette.seed,
            "near-black custom colors should derive a visible action fill"
        )

        let redPalette = ThemeResolver.resolve(.custom, customPrimary: ThemeColor(hex: 0xFF0000))
        expect(
            redPalette.actions.primaryFill.red > redPalette.actions.primaryFill.green,
            "saturated red should remain recognizably red after gamut and contrast adjustment"
        )
    }

    private static func testCustomInputClamping() {
        let color = ThemeColor(red: 1.5, green: -0.5, blue: .nan)
        expect(color.red == 1 && color.green == 0 && color.blue == 0, "invalid RGB input should clamp deterministically")
        verify(ThemeResolver.resolve(.custom, customPrimary: color), label: "clamped input")
    }

    private static func testLegacyPreferenceMigration() {
        let iceBlue = ThemeColor(hex: 0x2EA8FF)
        let jellyfinPurple = ThemeColor(hex: 0xAC5CC3)
        let customAccent = ThemeColor(red: 0.137, green: 0.263, blue: 0.419)
        let nearIceBlueAccent = ThemeColor(red: iceBlue.red + 0.0001, green: iceBlue.green, blue: iceBlue.blue)

        let arctic = ThemePreferenceMigration.resolve(
            existing: nil,
            migrationVersion: 0,
            legacyAccent: iceBlue
        )
        expect(arctic.identifier == .arctic, "default Ice Blue should migrate to Arctic")

        let purple = ThemePreferenceMigration.resolve(
            existing: nil,
            migrationVersion: 0,
            legacyAccent: jellyfinPurple
        )
        expect(purple.identifier == .custom, "stored Jellyfin Purple should migrate as Custom")
        expect(purple.customPrimary == jellyfinPurple, "migration should preserve the Jellyfin Purple seed")

        let custom = ThemePreferenceMigration.resolve(
            existing: nil,
            migrationVersion: 0,
            legacyAccent: customAccent
        )
        expect(custom.identifier == .custom, "non-default legacy accents should migrate as Custom")
        expect(custom.customPrimary == customAccent, "migration should preserve the full custom seed value")

        let nearIceBlue = ThemePreferenceMigration.resolve(
            existing: nil,
            migrationVersion: 0,
            legacyAccent: nearIceBlueAccent
        )
        expect(nearIceBlue.identifier == .custom, "a custom color near Ice Blue should not be mistaken for the default")
        expect(nearIceBlue.customPrimary == nearIceBlueAccent, "nearby custom colors should retain their exact seed")

        let selectedBeforeMigration = ThemePreference(identifier: .amethyst, customPrimary: nil)
        let existing = ThemePreferenceMigration.resolve(
            existing: selectedBeforeMigration,
            migrationVersion: 0,
            legacyAccent: jellyfinPurple
        )
        expect(existing == selectedBeforeMigration, "existing theme selection must win over legacy data")

        let repeated = ThemePreferenceMigration.resolve(
            existing: purple,
            migrationVersion: ThemePreferenceMigration.currentVersion,
            legacyAccent: iceBlue
        )
        expect(repeated == purple, "a completed migration must not reset an existing selection")

        let completedWithoutPreference = ThemePreferenceMigration.resolve(
            existing: nil,
            migrationVersion: ThemePreferenceMigration.currentVersion,
            legacyAccent: jellyfinPurple
        )
        expect(
            completedWithoutPreference == .applicationDefault,
            "a completed migration marker should not re-import stale legacy data"
        )
    }

    private static func testPerUserPreferenceResolution() {
        let userPreferences: [String: ThemePreference] = [
            "user-arctic": .arctic,
            "user-custom": .custom(primary: ThemeColor(hex: 0xAC5CC3)),
            "user-evergreen": ThemePreference(identifier: .evergreen, customPrimary: nil)
        ]

        let arctic = userPreferences["user-arctic"]?.palette
        let custom = userPreferences["user-custom"]?.palette
        let evergreen = userPreferences["user-evergreen"]?.palette

        expect(arctic?.identifier == .arctic, "Arctic user preference should resolve independently")
        expect(custom?.identifier == .custom, "Custom user preference should resolve independently")
        expect(custom?.seed.hex == 0xAC5CC3, "Custom user's seed should not be replaced by another user's theme")
        expect(evergreen?.identifier == .evergreen, "Evergreen user preference should resolve independently")
        expect(arctic != evergreen, "switching between different user preferences should change the palette")
    }

    private static func verify(_ palette: ThemePalette, label: String) {
        let textContrast = ThemeResolver.minimumTextContrast
        let essentialContrast = ThemeResolver.minimumEssentialContrast
        let surfaces = [
            palette.surfaces.canvas,
            palette.surfaces.elevated,
            palette.surfaces.elevatedHigh,
            palette.surfaces.playerOverlay
        ]

        for surface in surfaces {
            expect(palette.foregrounds.primary.contrastRatio(against: surface) >= textContrast, "primary text contrast failed for \(label)")
            expect(
                palette.foregrounds.secondary.contrastRatio(against: surface) >= textContrast,
                "secondary text contrast failed for \(label)"
            )
            expect(
                palette.foregrounds.disabled.contrastRatio(against: surface) >= textContrast,
                "disabled text contrast failed for \(label)"
            )
        }

        verifyPair(
            palette.actions.primaryFill,
            foreground: palette.actions.primaryForeground,
            background: palette.surfaces.canvas,
            label: "primary action \(label)"
        )
        verifyPair(
            palette.actions.primaryPressedFill,
            foreground: palette.actions.primaryPressedForeground,
            background: palette.surfaces.canvas,
            label: "pressed primary action \(label)"
        )
        verifyForeground(
            palette.actions.primaryDisabledFill,
            foreground: palette.actions.primaryDisabledForeground,
            label: "disabled primary action \(label)"
        )
        verifyForeground(
            palette.actions.secondaryFill,
            foreground: palette.actions.secondaryForeground,
            label: "secondary action \(label)"
        )
        verifyForeground(
            palette.actions.secondaryPressedFill,
            foreground: palette.actions.secondaryForeground,
            label: "pressed secondary action \(label)"
        )
        verifyForeground(
            palette.actions.secondaryDisabledFill,
            foreground: palette.actions.secondaryDisabledForeground,
            label: "disabled secondary action \(label)"
        )

        expect(
            palette.actions.secondaryBoundary.contrastRatio(against: palette.actions.secondaryFill) >= essentialContrast,
            "secondary action boundary contrast failed for \(label)"
        )
        expect(
            palette.actions.secondaryBoundary.contrastRatio(against: palette.surfaces.canvas) >= essentialContrast,
            "secondary action boundary vs canvas failed for \(label)"
        )
        expect(
            palette.focus.keylineOnSurface.contrastRatio(against: palette.surfaces.elevatedHigh) >= essentialContrast,
            "focus keyline on surfaces failed for \(label)"
        )
        expect(
            palette.focus.keylineOnPrimaryFill.contrastRatio(against: palette.actions.primaryFill) >= essentialContrast,
            "focus keyline on primary fill failed for \(label)"
        )
        expect(palette.focus.glowOpacity > 0, "focus glow should be independently configurable for \(label)")

        expect(
            palette.selection.indicator.contrastRatio(against: palette.surfaces.canvas) >= essentialContrast,
            "selection indicator contrast failed for \(label)"
        )
        expect(
            palette.selection.foreground.contrastRatio(against: palette.selection.background) >= textContrast,
            "selection text contrast failed for \(label)"
        )
        expect(
            palette.sidebar.selectedForeground.contrastRatio(against: palette.sidebar.selectedBackground) >= textContrast,
            "sidebar selected text contrast failed for \(label)"
        )
        expect(
            palette.sidebar.focusedForeground.contrastRatio(against: palette.sidebar.focusedBackground) >= textContrast,
            "sidebar focused text contrast failed for \(label)"
        )

        expect(
            palette.player.activeControlForeground.contrastRatio(against: palette.player.activeControl) >= textContrast,
            "player control foreground contrast failed for \(label)"
        )
        expect(
            palette.player.progress.contrastRatio(against: palette.surfaces.canvas) >= essentialContrast,
            "player progress contrast failed for \(label)"
        )
        expect(
            palette.player.completedProgress.contrastRatio(against: palette.surfaces.canvas) >= essentialContrast,
            "completed progress contrast failed for \(label)"
        )
        expect(
            palette.player.progressTrack.contrastRatio(against: palette.surfaces.canvas) >= essentialContrast,
            "progress track contrast failed for \(label)"
        )

        for status in [palette.status.success, palette.status.warning, palette.status.error, palette.status.information] {
            expect(status.contrastRatio(against: palette.surfaces.canvas) >= textContrast, "semantic status contrast failed for \(label)")
        }

        for color in allColors(in: palette) {
            expect((0 ... 1).contains(color.red), "red channel out of gamut for \(label)")
            expect((0 ... 1).contains(color.green), "green channel out of gamut for \(label)")
            expect((0 ... 1).contains(color.blue), "blue channel out of gamut for \(label)")
        }
    }

    private static func verifyPair(
        _ fill: ThemeColor,
        foreground: ThemeColor,
        background: ThemeColor,
        label: String
    ) {
        expect(
            fill.contrastRatio(against: background) >= ThemeResolver.minimumEssentialContrast,
            "fill/background contrast failed for \(label)"
        )
        expect(
            foreground.contrastRatio(against: fill) >= ThemeResolver.minimumTextContrast,
            "paired foreground contrast failed for \(label)"
        )
    }

    private static func verifyForeground(_ fill: ThemeColor, foreground: ThemeColor, label: String) {
        expect(
            foreground.contrastRatio(against: fill) >= ThemeResolver.minimumTextContrast,
            "disabled foreground contrast failed for \(label)"
        )
    }

    private static func allColors(in palette: ThemePalette) -> [ThemeColor] {
        [
            palette.seed,
            palette.surfaces.canvas,
            palette.surfaces.elevated,
            palette.surfaces.elevatedHigh,
            palette.surfaces.playerOverlay,
            palette.foregrounds.primary,
            palette.foregrounds.secondary,
            palette.foregrounds.disabled,
            palette.actions.primaryFill,
            palette.actions.primaryForeground,
            palette.actions.primaryPressedFill,
            palette.actions.primaryPressedForeground,
            palette.actions.primaryDisabledFill,
            palette.actions.primaryDisabledForeground,
            palette.actions.secondaryFill,
            palette.actions.secondaryForeground,
            palette.actions.secondaryPressedFill,
            palette.actions.secondaryBoundary,
            palette.actions.secondaryDisabledFill,
            palette.actions.secondaryDisabledForeground,
            palette.focus.keylineOnSurface,
            palette.focus.keylineOnPrimaryFill,
            palette.focus.glow,
            palette.selection.indicator,
            palette.selection.background,
            palette.selection.foreground,
            palette.sidebar.selectionIndicator,
            palette.sidebar.selectedBackground,
            palette.sidebar.selectedForeground,
            palette.sidebar.focusedBackground,
            palette.sidebar.focusedForeground,
            palette.sidebar.idleForeground,
            palette.player.activeControl,
            palette.player.activeControlForeground,
            palette.player.selectedControlBackground,
            palette.player.progress,
            palette.player.completedProgress,
            palette.player.progressTrack,
            palette.player.overlay,
            palette.status.success,
            palette.status.warning,
            palette.status.error,
            palette.status.information
        ]
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
