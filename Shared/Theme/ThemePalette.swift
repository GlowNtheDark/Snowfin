//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum ThemeIdentifier: String, CaseIterable, Hashable, Sendable {
    case arctic
    case amethyst
    case ember
    case evergreen
    case custom
}

/// An opaque sRGB color with deterministic contrast and perceptual-color helpers.
struct ThemeColor: Hashable, Sendable {

    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var hex: UInt32 {
        UInt32((red * 255).rounded()) << 16 |
            UInt32((green * 255).rounded()) << 8 |
            UInt32((blue * 255).rounded())
    }

    var relativeLuminance: Double {
        0.2126 * Self.linearize(red) +
            0.7152 * Self.linearize(green) +
            0.0722 * Self.linearize(blue)
    }

    func contrastRatio(against other: ThemeColor) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    fileprivate var oklch: OKLCH {
        let red = Self.linearize(red)
        let green = Self.linearize(green)
        let blue = Self.linearize(blue)

        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)

        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        return OKLCH(
            lightness: lightness,
            chroma: hypot(a, b),
            hue: atan2(b, a)
        )
    }

    fileprivate static func fromOKLCH(_ color: OKLCH) -> ThemeColor {
        let lightness = min(max(color.lightness, 0), 1)
        let hue = color.hue.isFinite ? color.hue : 0
        let requestedChroma = max(color.chroma.isFinite ? color.chroma : 0, 0)

        func candidate(chroma: Double) -> (red: Double, green: Double, blue: Double) {
            let a = chroma * cos(hue)
            let b = chroma * sin(hue)

            let l = lightness + 0.3963377774 * a + 0.2158037573 * b
            let m = lightness - 0.1055613458 * a - 0.0638541728 * b
            let s = lightness - 0.0894841775 * a - 1.2914855480 * b

            let l3 = l * l * l
            let m3 = m * m * m
            let s3 = s * s * s

            let linearRed = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
            let linearGreen = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
            let linearBlue = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

            return (linearRed, linearGreen, linearBlue)
        }

        func isInGamut(_ rgb: (red: Double, green: Double, blue: Double)) -> Bool {
            rgb.red >= 0 && rgb.red <= 1 &&
                rgb.green >= 0 && rgb.green <= 1 &&
                rgb.blue >= 0 && rgb.blue <= 1
        }

        var chroma = requestedChroma
        var rgb = candidate(chroma: chroma)

        if !isInGamut(rgb) {
            var lower = 0.0
            var upper = chroma

            for _ in 0 ..< 28 {
                let midpoint = (lower + upper) / 2
                if isInGamut(candidate(chroma: midpoint)) {
                    lower = midpoint
                } else {
                    upper = midpoint
                }
            }

            chroma = lower
            rgb = candidate(chroma: chroma)
        }

        return ThemeColor(
            red: Self.encode(rgb.red),
            green: Self.encode(rgb.green),
            blue: Self.encode(rgb.blue)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func linearize(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

private struct OKLCH {
    var lightness: Double
    var chroma: Double
    var hue: Double
}

struct ThemePalette: Hashable, Sendable {

    let identifier: ThemeIdentifier
    let seed: ThemeColor
    let surfaces: SurfaceTokens
    let foregrounds: ForegroundTokens
    let actions: ActionTokens
    let focus: FocusTokens
    let selection: SelectionTokens
    let sidebar: SidebarTokens
    let player: PlayerTokens
    let status: StatusTokens

    struct SurfaceTokens: Hashable, Sendable {
        let canvas: ThemeColor
        let elevated: ThemeColor
        let elevatedHigh: ThemeColor
        let playerOverlay: ThemeColor
    }

    struct ForegroundTokens: Hashable, Sendable {
        let primary: ThemeColor
        let secondary: ThemeColor
        let disabled: ThemeColor
    }

    struct ActionTokens: Hashable, Sendable {
        let primaryFill: ThemeColor
        let primaryForeground: ThemeColor
        let primaryPressedFill: ThemeColor
        let primaryPressedForeground: ThemeColor
        let primaryDisabledFill: ThemeColor
        let primaryDisabledForeground: ThemeColor
        let secondaryFill: ThemeColor
        let secondaryForeground: ThemeColor
        let secondaryPressedFill: ThemeColor
        let secondaryBoundary: ThemeColor
        let secondaryDisabledFill: ThemeColor
        let secondaryDisabledForeground: ThemeColor
    }

    struct FocusTokens: Hashable, Sendable {
        /// Contrasts with the dark surface outside a focused control.
        let keylineOnSurface: ThemeColor
        /// Contrasts with the primary fill inside a focused control.
        let keylineOnPrimaryFill: ThemeColor
        let glow: ThemeColor
        let glowOpacity: Double
        let glowRadius: Double
    }

    struct SelectionTokens: Hashable, Sendable {
        let indicator: ThemeColor
        let background: ThemeColor
        let foreground: ThemeColor
    }

    struct SidebarTokens: Hashable, Sendable {
        let selectionIndicator: ThemeColor
        let selectedBackground: ThemeColor
        let selectedForeground: ThemeColor
        let focusedBackground: ThemeColor
        let focusedForeground: ThemeColor
        let idleForeground: ThemeColor
    }

    struct PlayerTokens: Hashable, Sendable {
        let activeControl: ThemeColor
        let activeControlForeground: ThemeColor
        let selectedControlBackground: ThemeColor
        let progress: ThemeColor
        let completedProgress: ThemeColor
        let progressTrack: ThemeColor
        let overlay: ThemeColor
    }

    struct StatusTokens: Hashable, Sendable {
        let success: ThemeColor
        let warning: ThemeColor
        let error: ThemeColor
        let information: ThemeColor
    }
}

/// Resolves a stable semantic palette without reading or mutating app, view, or navigation state.
enum ThemeResolver {

    static let defaultIdentifier: ThemeIdentifier = .arctic
    static let minimumTextContrast = 4.5
    static let minimumEssentialContrast = 3.0

    private static let arcticSeed = ThemeColor(hex: 0x2EA8FF)
    private static let deepNavy = ThemeColor(hex: 0x010305)
    private static let white = ThemeColor(hex: 0xFFFFFF)
    private static let black = ThemeColor(hex: 0x000000)
    private static let hueFallback = arcticSeed.oklch.hue

    static func resolve(
        _ identifier: ThemeIdentifier,
        customPrimary: ThemeColor? = nil
    ) -> ThemePalette {
        let seed = seed(for: identifier, customPrimary: customPrimary)
        let seedLCH = seed.oklch
        let hue = seedLCH.chroma < 0.012 ? hueFallback : seedLCH.hue
        let baseChroma = seedLCH.chroma < 0.012 && seedLCH.lightness < 0.2 ? 0.12 : seedLCH.chroma

        let canvas = identifier == .arctic ? deepNavy : surface(
            lightness: deepNavy.oklch.lightness,
            hue: hue,
            chroma: 0.008
        )
        let elevated = surface(
            lightness: deepNavy.oklch.lightness + 0.045,
            hue: hue,
            chroma: 0.012
        )
        let elevatedHigh = surface(
            lightness: deepNavy.oklch.lightness + 0.085,
            hue: hue,
            chroma: 0.016
        )

        let primaryFill = accessibleActionColor(
            lightness: seedLCH.lightness,
            chroma: baseChroma,
            hue: hue,
            background: canvas
        )
        let primaryForeground = bestContrastColor(against: primaryFill)
        let primaryPressedFill = accessibleActionColor(
            lightness: max(primaryFill.oklch.lightness - 0.045, 0),
            chroma: primaryFill.oklch.chroma,
            hue: primaryFill.oklch.hue,
            background: canvas
        )
        let primaryPressedForeground = bestContrastColor(against: primaryPressedFill)

        let primaryText = white
        let secondaryText = ThemeColor(hex: 0xC4CBD5)
        let disabledText = ThemeColor(hex: 0xAAB3C0)
        let primaryDisabledFill = ThemeColor(hex: 0x303A48)
        let primaryDisabledForeground = ThemeColor(hex: 0xE0E5EC)
        let secondaryDisabledFill = ThemeColor(hex: 0x252D39)
        let secondaryDisabledForeground = ThemeColor(hex: 0xD0D7E0)

        let selectedBackground = mix(elevated, primaryFill, amount: 0.13)
        let focusedBackground = elevatedHigh
        let selectionForeground = ensureTextContrast(primaryText, against: selectedBackground)
        let accentText = ensureTextContrast(primaryFill, against: canvas)

        let success = ensureTextContrast(ThemeColor(hex: 0x30D158), against: canvas)
        let warning = ensureTextContrast(ThemeColor(hex: 0xFFD60A), against: canvas)
        let error = ensureTextContrast(ThemeColor(hex: 0xFF453A), against: canvas)
        let information = ensureTextContrast(ThemeColor(hex: 0x64D2FF), against: canvas)
        let secondaryBoundary = ensureContrast(
            ThemeColor(hex: 0x657080),
            against: elevatedHigh,
            minimum: minimumEssentialContrast
        )
        let progressTrack = ensureContrast(
            ThemeColor(hex: 0x4A5361),
            against: canvas,
            minimum: minimumEssentialContrast
        )

        let completedProgress = accessibleActionColor(
            lightness: min(primaryFill.oklch.lightness + 0.12, 1),
            chroma: primaryFill.oklch.chroma * 0.72,
            hue: primaryFill.oklch.hue + 0.48,
            background: canvas
        )

        return ThemePalette(
            identifier: identifier,
            seed: seed,
            surfaces: .init(
                canvas: canvas,
                elevated: elevated,
                elevatedHigh: elevatedHigh,
                playerOverlay: canvas
            ),
            foregrounds: .init(
                primary: primaryText,
                secondary: secondaryText,
                disabled: disabledText
            ),
            actions: .init(
                primaryFill: primaryFill,
                primaryForeground: primaryForeground,
                primaryPressedFill: primaryPressedFill,
                primaryPressedForeground: primaryPressedForeground,
                primaryDisabledFill: primaryDisabledFill,
                primaryDisabledForeground: primaryDisabledForeground,
                secondaryFill: elevated,
                secondaryForeground: primaryText,
                secondaryPressedFill: elevatedHigh,
                secondaryBoundary: secondaryBoundary,
                secondaryDisabledFill: secondaryDisabledFill,
                secondaryDisabledForeground: secondaryDisabledForeground
            ),
            focus: .init(
                keylineOnSurface: bestContrastColor(against: elevatedHigh),
                keylineOnPrimaryFill: bestContrastColor(against: primaryFill),
                glow: primaryFill,
                glowOpacity: 0.28,
                glowRadius: 16
            ),
            selection: .init(
                indicator: primaryFill,
                background: selectedBackground,
                foreground: selectionForeground
            ),
            sidebar: .init(
                selectionIndicator: primaryFill,
                selectedBackground: selectedBackground,
                selectedForeground: ensureTextContrast(accentText, against: selectedBackground),
                focusedBackground: focusedBackground,
                focusedForeground: primaryText,
                idleForeground: secondaryText
            ),
            player: .init(
                activeControl: primaryFill,
                activeControlForeground: primaryForeground,
                selectedControlBackground: selectedBackground,
                progress: primaryFill,
                completedProgress: completedProgress,
                progressTrack: progressTrack,
                overlay: canvas
            ),
            status: .init(
                success: success,
                warning: warning,
                error: error,
                information: information
            )
        )
    }

    private static func seed(
        for identifier: ThemeIdentifier,
        customPrimary: ThemeColor?
    ) -> ThemeColor {
        switch identifier {
        case .arctic:
            arcticSeed
        case .amethyst:
            ThemeColor(hex: 0xA889F7)
        case .ember:
            ThemeColor(hex: 0xFF825A)
        case .evergreen:
            ThemeColor(hex: 0x45C98A)
        case .custom:
            customPrimary ?? arcticSeed
        }
    }

    private static func surface(lightness: Double, hue: Double, chroma: Double) -> ThemeColor {
        ThemeColor.fromOKLCH(.init(lightness: lightness, chroma: chroma, hue: hue))
    }

    private static func accessibleActionColor(
        lightness: Double,
        chroma: Double,
        hue: Double,
        background: ThemeColor
    ) -> ThemeColor {
        let start = min(max(lightness, 0), 1)
        let chroma = max(chroma, 0)

        func candidate(at lightness: Double) -> ThemeColor {
            ThemeColor.fromOKLCH(.init(lightness: lightness, chroma: chroma, hue: hue))
        }

        func passes(_ color: ThemeColor) -> Bool {
            color.contrastRatio(against: background) >= minimumEssentialContrast &&
                bestContrastColor(against: color).contrastRatio(against: color) >= minimumTextContrast
        }

        let initial = candidate(at: start)
        guard !passes(initial) else { return initial }

        var lower = start
        var upper = 1.0
        for _ in 0 ..< 28 {
            let midpoint = (lower + upper) / 2
            if passes(candidate(at: midpoint)) {
                upper = midpoint
            } else {
                lower = midpoint
            }
        }

        let resolved = candidate(at: upper)
        return passes(resolved) ? resolved : white
    }

    private static func ensureTextContrast(_ foreground: ThemeColor, against background: ThemeColor) -> ThemeColor {
        ensureContrast(foreground, against: background, minimum: minimumTextContrast)
    }

    private static func ensureContrast(
        _ foreground: ThemeColor,
        against background: ThemeColor,
        minimum: Double
    ) -> ThemeColor {
        guard foreground.contrastRatio(against: background) < minimum else { return foreground }

        let lch = foreground.oklch
        let hue = lch.chroma < 0.012 ? hueFallback : lch.hue
        let chroma = lch.chroma

        var best: ThemeColor?
        var bestDistance = Double.infinity

        for step in 0 ... 1000 {
            let candidateLightness = Double(step) / 1000
            let candidate = ThemeColor.fromOKLCH(.init(
                lightness: candidateLightness,
                chroma: chroma,
                hue: hue
            ))
            guard candidate.contrastRatio(against: background) >= minimum else { continue }

            let distance = abs(candidateLightness - lch.lightness)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }

        return best ?? bestContrastColor(against: background)
    }

    private static func bestContrastColor(against background: ThemeColor) -> ThemeColor {
        white.contrastRatio(against: background) >= black.contrastRatio(against: background) ? white : black
    }

    private static func mix(_ first: ThemeColor, _ second: ThemeColor, amount: Double) -> ThemeColor {
        let firstLab = first.oklch
        let secondLab = second.oklch
        let deltaHue = shortestAngle(from: firstLab.hue, to: secondLab.hue)

        return ThemeColor.fromOKLCH(.init(
            lightness: firstLab.lightness + (secondLab.lightness - firstLab.lightness) * amount,
            chroma: firstLab.chroma + (secondLab.chroma - firstLab.chroma) * amount,
            hue: firstLab.hue + deltaHue * amount
        ))
    }

    private static func shortestAngle(from first: Double, to second: Double) -> Double {
        var delta = (second - first).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        return delta
    }
}
