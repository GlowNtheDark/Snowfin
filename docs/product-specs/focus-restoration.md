# Focus restoration

Status: explicit timing contract; fallback order reflects current implementation.

Restore Home focus only after navigation actually returns to Home. While Episode
Details remains presented after player dismissal, keep the Home target dormant.
Preserve the launch tile identity across refresh/reordering without collapsing screens.

Prefer the originating tile. When it disappears, current TV behavior chooses:

1. If the origin was in Continue Watching, a replacement with the same nonempty series ID in that row.
2. The nearest remaining tile in the original row.
3. The first available tile in the ordered Home rows.

For an unchanged tile, retain it even if its index changes. Reveal virtualized/offscreen
content before requesting focus, and avoid letting sidebar focus interrupt the return.
Initial Home entry, details-local focus, and Search entry are separate concerns.

See [focus mechanics](../design-docs/focus-system.md) and the required
[interaction checks](../QUALITY.md). The timing contract is mandatory; the current
fallback implementation still requires runtime evidence for a given change.
