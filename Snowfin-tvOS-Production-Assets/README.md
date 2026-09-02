# Snowfin tvOS Production Asset Pack

Final production artwork for Snowfin on tvOS. Apple/tvOS logos are intentionally absent. All raster backgrounds are full-bleed RGB; all foregrounds are RGBA; vectors are tvOS-only SVGs.

## Color reference

- Snowfin Ice Blue: `#2EA8FF` (RGB 46, 168, 255)
- Recommended deep-navy base: `#041426` (RGB 4, 20, 38)

## Exact Xcode slot map

| Existing Xcode asset / slot | Supplied file |
|---|---|
| `App Icon.imagestack` → foreground, tv 1× | `AppIcon-foreground-216.png` |
| `App Icon.imagestack` → foreground, tv 2× | `AppIcon-foreground-432.png` |
| `App Icon.imagestack` → background, tv 1× | `AppIcon-background-400x240.png` |
| `App Icon.imagestack` → background, tv 2× | `AppIcon-background-800x480.png` |
| `App Icon - App Store.imagestack` → foreground | `AppStore-foreground-512.png` |
| `App Icon - App Store.imagestack` → background | `AppStore-background-1280x768.png` |
| `Top Shelf Image.imageset` → tv runtime 1× and tv-marketing 1× | `TopShelf-standard-1920x720.png` |
| `Top Shelf Image.imageset` → tv runtime 2× and tv-marketing 2× | `TopShelf-standard-3840x1440.png` |
| `Top Shelf Image Wide.imageset` → tv runtime 1× and tv-marketing 1× | `TopShelf-wide-2320x720.png` |
| `Top Shelf Image Wide.imageset` → tv runtime 2× and tv-marketing 2× | `TopShelf-wide-4640x1440.png` |

Do not rename catalog containers or alter their `Contents.json` semantics. Map supplied artwork to the existing filenames referenced by each manifest.

The standard Top Shelf protects all important branding inside the centered 1536×576 region at 1× (384 px horizontal / 144 px vertical inset at 2×). The wide artwork protects it inside centered 1760×576 at 1×, leaving at least 280 px horizontally and 72 px vertically free of critical content (double those values at 2×).

## In-app branding

- `snowfin-tvOS-mark.svg`: Option A, square mark only. Use this for the large left-side Settings identity on tvOS.
- `snowfin-tvOS-brand.svg`: optional mark + Snowfin wordmark for a future Option B. No tagline.

Use a new, unambiguous tvOS-only asset identifier such as `snowfin-tvOS-mark`. Do not overwrite or reuse shared `jellyfin-blob-blue`; it is shared across platforms and surfaces.

## tvOS-only implementation guidance

Apply Snowfin Ice Blue `#2EA8FF` as the tvOS default accent. Migrate a stored accent only when its normalized value is exactly legacy Jellyfin purple `#AC5CC3` (case-insensitive, with or without alpha if the project stores alpha separately). Preserve every other stored/custom color.

Give tvOS Settings a deep navy `#041426` base with an optional subtle, non-interactive atmospheric layer (low-opacity cyan/aurora glow or soft snow haze). Keep contrast high and controls native. Gate the logo, accent-default migration, and Settings treatment through tvOS-specific compilation/target code so iOS appearance and assets remain untouched.

## Codex installation prompt

> Install the production assets from `Snowfin-tvOS-Production-Assets/` into the existing `Swiftfin tvOS` target only. Read this README first. Preserve the current Xcode asset catalog container names, slot semantics, filenames referenced by each `Contents.json`, Swiftfin internals, playback architecture, schemes, targets, identifiers, and every iOS asset/behavior. Copy each supplied PNG into the matching existing tvOS icon or Top Shelf slot; do not edit or regenerate the artwork. Add the SVG mark under a new unambiguous tvOS-only image asset named exactly `snowfin-tvOS-mark`, and retain `snowfin-tvOS-brand` as an unused tvOS-only Option B asset without wiring it into Settings. Update only the tvOS Settings branding to use `snowfin-tvOS-mark` on the left. Make Snowfin Ice Blue `#2EA8FF` the tvOS default accent and migrate only stored legacy Jellyfin purple `#AC5CC3`; preserve all genuinely customized colors. Apply a tvOS-only deep navy Settings background with a subtle low-opacity atmospheric treatment; do not affect iOS. Do not rename Swiftfin internals. Build the `Swiftfin tvOS` scheme for a generic tvOS Simulator, report asset-catalog warnings/errors and the exact files changed, and leave every change uncommitted for simulator validation.

`checksums.json` contains SHA-256 hashes for transfer verification.
