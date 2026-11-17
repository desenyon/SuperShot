# Settings, setup, and pins — 2026-11-16

## Changes

Settings now uses neutral grouped surfaces, plain icons, smaller headings, compact appearance choices, and searchable navigation. The supplied panel reference informed density, grouping, and restraint; no assets or branding were copied. Dark and light palettes are explicit. The design pass followed the unslop skill by Damir Sokolovsky.

The previous welcome marketing page is replaced with a small permission setup. A separate persisted setup flag is claimed before showing it, so closing it, restarting, or recovering corrupt preferences does not show it again. Users who already granted access or completed onboarding skip setup. Reopening the app opens Settings. The menu's Welcome command is removed.

New settings are connected to the capture controller: thumbnail corner, width, dismissal delay (paused while hovered), pin initial size, opacity, window shadow, and all-Spaces behavior. Scrolling captures now expose their existing per-mode action override. Defaults migrate from older preference files; invalid floating settings use the existing backup/recovery path. Slider feedback stays in view state until release, avoiding full preference serialization on every tick.

Pins use native window dragging and explicit resize events at every edge and corner. Geometry preserves image proportions and anchors the opposite edge/corner, clamps size, and fits the available screen. Double-click restores size. Arrow keys move a focused pin; +/- resize; 0 restores. Hover controls expose opacity, lock, copy, and close, with a compact menu at narrow widths. A resize affordance remains visible. Lock recovery stays in the app menu. Closing a pin releases it from its controller.

The bundle script now defaults to optimized release, stamps build metadata, supports BUNDLE_OUTPUT_DIR, and refuses to overwrite the running app. The signed 0.4.0 build was staged at `dist/Updated/SuperShot.app`. After explicit user approval, SuperShot quit normally through its save-flushing termination handler, the update was installed at `dist/SuperShot.app`, and Settings was reopened. The old bundle is preserved at `dist/Previous/SuperShot-20261116-165016.app`. The window server confirmed the new process (PID 73205) has a visible SuperShot Settings window.

## Checks performed

- `swift build --jobs 2` passed.
- `scripts/test-background.sh` passed **63 tests across 11 test targets**. Six new regressions cover one-time setup, existing-user setup suppression, persisted floating settings, old preferences, invalid preference recovery, pin aspect/anchor geometry, size limits, portrait fitting, and edge detection. (Three settings tests and three geometry tests.)
- Existing tests cover document edits, rendering snapshots, synthetic scroll stitching, exports, OCR/QR, library storage, settings, shortcut logic, and local AI helpers. The recorder-window test remains excluded.
- `scripts/preview.sh` completed. Main surfaces were regenerated in both appearances, including full-height settings pages, a minimum-size settings window, denied/granted setup, and pin controls. Settings/setup/pin PNGs were inspected in both appearances. Contact sheets are `docs/previews/review-dark.png` and `review-light.png`.
- Optimized bundle build and `codesign --verify --deep --strict --verbose=2` passed. Mach-O UUIDs match the built release executable. Signature bytes differ as expected because the bundle receives the stable development signature.
- `zsh -n scripts/bundle.sh` passed.

Raw evidence: [tests](settings-pins-evidence/tests.log), [bundle](settings-pins-evidence/bundle.log), [benchmark](settings-pins-evidence/benchmark.log).

## Performance measurement

`scripts/benchmark.sh` used the existing synthetic 5120 × 2880 image with 200 vector layers. Five raster samples at 2200px were 113.5, 12.0, 12.4, 13.2, and 24.6 ms. At full 5120px they were 33.7, 30.8, 20.5, 11.0, and 12.6 ms. These are individual render costs, not end-to-end editor frame rates.

First measured OCR calls were 657.1 ms (fast) and 441.6 ms (accurate); subsequent calls were 241.3 and 298.5 ms. All returned 24 regions. Cold recognition remains over the 300 ms target. This synthetic fixture does not establish OCR accuracy on arbitrary captures, and no claim of universal 60 fps or sub-100 ms capture latency is made.

## Pending interactive coverage

Background checks made no shared clipboard writes, synthetic desktop input, capture overlays, permission prompts, or app restarts. A later, explicitly authorized normal quit/install/relaunch confirmed that Settings opens in the installed 0.4.0 build; it did not exercise capture or pin interactions. Offscreen previews use the opaque glass fallback. Actual pin dragging/resizing, click-through recovery, thumbnail drag/drop and timers, real capture/export/clipboard flows, login registration, and real Liquid Glass still need an authorized interactive session or isolated macOS desktop. Passing tests do not verify every feature end to end.

The roadmap still includes unimplemented or conditional features documented in README: cloud AI, downloaded generative models, horizontal stitching, video/GIF and share links; Apple Intelligence and translation require installed system support.

## Apple API references

Native dragging uses [NSWindow.performDrag(with:)](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)). Explicit resizing uses [NSWindow.setFrame(_:display:)](https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:)). The custom interaction view accepts the initial click using [NSView.acceptsFirstMouse(for:)](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:)). Documentation was checked before implementing the event path.
