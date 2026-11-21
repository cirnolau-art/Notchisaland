# NotchIsland appearance and lyrics implementation plan

Approved specification: the eight-part request in the current chat.

Goal: stable lyric visibility, clean native glass, reversible full retraction, font-aware layout, independent timed-word fades and optional genuine EDR content. macOS 15 minimum; no private APIs, dependencies, publishing or Git pushes.

- [x] Regression tests: prelude visibility, full retraction/restore and transient suppression, continuous word timing, legacy preferences, HDR bounds, text geometry.
- [x] Add reusable LyricHighlight timeline and cached CoreText glyph row. SDR uses per-word Core Animation opacity; HDR uses floating-point extended-linear-sRGB images on EDR-enabled CALayers. No continuous redraw timer.
- [x] Integrate rows into LyricRollView; preserve source timings, carry in-flight scroll positions, feather expanded edges; use measured text height.
- [x] Fix compact visibility ordering/cancelled hide races. Detach idle render resources when hidden; preserve lyric rows across refreshes.
- [x] Simplify native glass, align native geometry with animated clip, soften opaque camera mask, remove default artificial rim, synchronise understated black shadow.
- [x] Independent full-retraction policy, pinch event routing and vertical fallback, gated hover/transients/notifications, restore valid prior panel.
- [x] Settings: genuine HDR toggle and intensity; honest material descriptions and gesture help; keep legacy saved appearance compatible.
- [x] Run tests and packaged visual/interaction diagnostics; native on-screen glass and animation checks where available, EDR content and headroom probe. Report unavailable physical HDR/multi-OS checks honestly.
- [x] Copy reviewed changes to original repository with required filesystem authorization, verify diff, leave uncommitted and unpublished.
