# SuperShot Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Check off verified work only.

**Goal:** Build the native screenshot application specified in AGENTS.md, advancing only after each milestone passes its acceptance gate.
**Architecture:** AppKit owns the app lifecycle and windows. SwiftUI owns panels and settings. Library targets isolate design tokens, preferences, capture, documents, rendering and subsequent subsystems.
**Tech Stack:** Swift 6, macOS 26+, Apple frameworks, Swift Package Manager; no third-party dependencies.
**Spec:** ../../../AGENTS.md

## Global Constraints
- Native macOS only, deployment target macOS 26.
- No dependencies, telemetry, or app network calls.
- Stable signing; original images immutable; UI on main actor.
- Real visual inspection in dark and light appearance before advancing.

## Review Focus
- Denied or revoked permission must never appear as authorized.
- Closing a window must retain a reachable menu-bar application.
- Corrupt preferences must recover safely and preserve the original file.
- Appearance changes must apply to existing and future windows.
- Repeated bundles must preserve the signing designated requirement.

## Milestone 1: Shell and permissions
- [x] Create Package.swift, DesignSystem, Settings, Capture permission service, SuperShotApp and per-target tests.
- [x] Test settings round trips, defaults, invalid data recovery and permission transitions before implementation.
- [x] Build shared typography, geometry, accent, materials and motion tokens; create original onboarding illustration.
- [x] Implement native menu-bar lifecycle, permission onboarding and live permission refresh, appearance controls and settings.
- [x] Assemble app resources and Info.plist. Provide stable local signing setup and bundle scripts; verify signature stability over two builds.
- [x] Run swift build and swift test; run bundled app; inspect onboarding and settings in both appearances; exercise menu/window lifecycle and permission states.
- [x] Record evidence and only then advance to milestone 2. If OS authorization needs user action, prepare the app completely before requesting it.

## Subsequent milestone gates
2. Capture: ScreenCaptureKit screen/window/area, frozen overlay, Carbon hotkeys, after-capture dispatch, thumbnails and export; tests for coordinates and action logic, live captures.
3. Editor: headless document and shared renderer, tool protocol, canvas, shapes/text/freehand/crop and undo; round trips and renderer image snapshots, live edits and exports.
4. Backdrop: fills, geometry, corner radius and shadows; same renderer in preview and export; visual checks.
5. Advanced tools and pins: implement per-tool layers with verified rendering, then interactions.
6. Vision recognition and history: OCR/barcode, persistent text index, real sample fixtures.
7. Scrolling: robust overlap detection and failure reporting; fixture stitching and live scrolling verification.
8. AI: local tier first. No network or downloaded dependencies without consent.
9. Integration: login items, shortcut profiles, intents, accessibility, measured performance.

## Execution ledger
- Repository begins as three design files, without .git. Preserve those files and work in place; no commits or worktrees possible until a repository is initialized.
- macOS 27.2, Swift 6.4, Command Line Tools. No valid code-signing identities at start.
- Foundation: scripts/test.sh passes 7 tests across 3 targets. Initial red run was blocked by missing XCTest; converted to Swift Testing with a CLT plugin wrapper.
- Stable identity created in ignored project-local keychain. Two builds, with changed executable content, retained certificate leaf e913487d4ca36437c0e82782ae7f60c12d000be3. codesign verification passed.
- Native UI inspected through Computer Use. Fixed NSHostingView unbounded sizing; final content uses explicit dimensions and disabled automatic sizing. Both settings appearances inspected. User granted Screen Recording and app observed authorization on 2026-11-15.

- Capture core: 17 tests pass, including recorder-window closure. Live screen, exact 800x600 area, PNG clipboard/save, and real window capture verified. Native settings in both appearances were inspected; final scrollability fix awaits another live pass.
- Capture review fixes: shortcut recording cancellation on window close, window-mode Return, copy generation ordering, thumbnail reflow, selection move anchor. Stable bundle replacement survives an invalid signing identity.
- Editor model and compositor: 25 tests pass across eight targets. Non-destructive layers, branching undo, project version handling, top-left crop/color probes, and renderer repeatability verified.
- Ruling: Desktop inspection now repeatedly returns `Computer Use server error -10005: timeoutReached`. Continue headless model, renderer, and editor implementation while retrying the tool; do not mark UI milestones complete until visual inspection resumes.
- Ruling: The initial compositor converts output to sRGB. Display-profile preservation remains a later export setting; the info panel explicitly says sRGB rather than claiming preservation.

- User steering: keep building and auditing, test last. All further automated and live test runs are deferred until the implementation/audit pass is assembled.
- Implemented recognition, history, local AI actions, vertical scrolling session/stitcher, pins, format/clipboard settings, sidecars, filename templates, shortcut profiles, preset shortcuts, launch at login, and URL routing. These additions remain unverified until the final test pass.
- Code audit fixes: history inserts cannot overwrite an existing edit; copy generation remains ordered; AI results are discarded if the document changed; rendering cancellation propagates; invalid project geometry is rejected; native photo orientation is respected; same-document saves carry matching sidecars; auto backdrops affect output actions; pixel-grid loops are viewport bounded.
- Ruling: Cloud provider network calls and downloaded third-party models are not added, per the explicit project rule requiring permission. Local AI uses installed Apple facilities and reports unavailable models/languages honestly. Upscaling is labeled resampling; object removal is labeled patch erase.
- Ruling: Command Line Tools does not include appintentsmetadataprocessor. Intent source and a registered URL scheme are provided; Shortcuts can use Open URLs. Native action discovery cannot be claimed from this toolchain.

## Final audit and verification — 2026-11-16

- Implementation/audit pass is assembled. Final verification follows the user's instruction to test last; fixes found during that pass receive focused regressions before the last full run.
- Final review corrections cover original-overwriting-edits, sidecar collisions, geometry/counter validation, full-resolution zoom and picking, transformed effects, stale redaction proposals, odd-pixel stitching, scroll task identity, and quit-time save flushing. See the detailed evidence matrix in `docs/verification/2026-11-16.md`.
- Live fixture editing, OCR/QR, redaction, project save, clipboard, and PNG export succeeded. Editor, settings, and welcome appearances were inspected in dark and light. Final small UI adjustments remain visually unchecked because Computer Use now returns `cgWindowNotFound` for both the app and an independent fixture.
- A synthetic 5K benchmark exposed fast OCR's minimum-height bug and repeated base-image decoding. After fixes, all 24 rows are recognized and warm vector-layer renderer calls measure about 8–9 ms. Cold model compilation and full interactive/effect-heavy performance remain distinct open gates.
- Ruling: Completion is reported at the implemented local development-build scope. Full product milestone acceptance is not asserted while the visual, multi-display, permission, and performance gates listed in the verification report remain open.
- Final automation: 48 tests pass across all 11 test targets with exit status 0. Release bundle succeeds, strict signature verification passes, and the certificate designated requirement is unchanged. Source warnings about implicit capture were resolved; CLT linker search-path warnings remain.

- Desktop access recovered. Final live checks verified manual three-frame stitching, pin menu and keyboard closing, OCR phrase search despite split words, native text-edit shortcuts, text annotation persistence across immediate quit/relaunch, and dark/light editor, settings, library, pins, scrolling, and intelligence surfaces. The last regression suite passes 49 tests across 11 targets; the final release signature verifies. The app is left open in Dark appearance. Advanced product-spec and OS integration gaps remain explicitly listed in the report.
