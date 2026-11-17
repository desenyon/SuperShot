# Quick capture and audit — SuperShot 0.4.1

## Behavior

Settings → Capture → Quick capture now offers two independent switches, both defaulting off and preserved across restarts:

- **Automatically copy screenshots:** adds copying to screen, window, area, previous-area, timed-area, all-display, and scrolling image captures. Editor, thumbnail, save, and pin choices remain intact. Per-mode overrides and explicit overlay image actions also receive auto-copy. Text recognition and barcode flows remain separate.
- **Capture on mouse release:** a new area drag captures when released, using the final release coordinates. It does not fire on a click, zero-area drag, cancellation, or repeated release/Enter event. With the switch off, Enter still confirms. Typed exact-size selections can be adjusted and confirmed with Enter even when the switch is on. Window, text, barcode, and scrolling selection retain their existing behavior.

The overlay's visual and accessibility instructions reflect release-to-capture behavior. No additional work runs during dragging except existing selection calculations; encoding stays off the main actor.

## Audit fixes

- Area selection completion is one-shot, preventing duplicate callbacks from late mouse or key events.
- Mouse-up consumes the final event coordinates, fixing a stale last-drag position when events are coalesced.
- Capture sessions stay busy through their asynchronous outputs so an old completion cannot clear a newer session's busy state.
- After-capture actions use explicit capture modes rather than inferring mode from an app/window source string.
- Clipboard writes reserve a request before backdrop rendering and encoding. Older requests are discarded if a newer copy is requested or the pasteboard changes in the meantime. Failed or empty data preparation preserves existing clipboard contents; write failures are surfaced.
- Filename limits use UTF-8 bytes while preserving whole characters, so long CJK and emoji window titles fit filesystem limits. Token values are expanded once, avoiding accidental reinterpretation of token-shaped text within window/app titles.
- Nonfinite, zero, negative, and oversized resampling factors throw an export error before any unsafe conversion to Int.

## Verification

`scripts/test-background.sh` passed **75 tests across 11 targets**. Twelve regressions were added: two settings/action-policy tests, five direct overlay-event tests, three isolated clipboard tests, and two export validation tests. Existing document, renderer snapshots, editor, recognition, history, scrolling, hotkey, and AI helper tests also passed.

Overlay tests call AppKit handlers on detached views using local synthetic event objects; they never post mouse or keyboard input. Clipboard tests use uniquely named pasteboards, never `NSPasteboard.general`. The initial event fixture used the wrong vertical coordinate convention; it was corrected to map its test points to AppKit window coordinates before the successful run.

`scripts/preview.sh` completed. Capture settings in both off/on states, the 680 × 440 settings layout, and the quick-capture overlay were inspected in dark and light. Other main-surface previews were regenerated. These images use the offscreen glass fallback.

The optimized release bundle passed stable-signature verification. The user explicitly approved installation. SuperShot quit normally, 0.4.1 was installed at `dist/SuperShot.app`, and the window server confirmed a visible Settings window in PID 77297. Installed and built release executables share Mach-O UUID `39C450D7-CD3E-38D0-9411-52AE20C333D8`. The previous build is preserved at `dist/Previous/SuperShot-20261116-170322.app`.

Evidence: [test log](quick-capture-evidence/tests.log), [bundle log](quick-capture-evidence/bundle.log), [Capture settings](../previews/settings-capture-dark.png), [enabled settings](../previews/settings-quick-capture-light.png), [quick overlay](../previews/overlay-quick-dark.png).

## Remaining boundary

The actual screen-capture-to-paste workflow was not exercised on the shared desktop. The tests establish action resolution, selection events/crop coordinates, encoding/pasteboard round trips, persistence, and regressions; they do not establish universal live capture accuracy, all application paste compatibility, OS permission behavior, or frame-rate budgets. No shared clipboard content or user preferences were changed during verification. Both new switches remain off in the installed app until enabled by the user.

Clipboard behavior was checked against Apple's [NSPasteboard](https://developer.apple.com/documentation/AppKit/NSPasteboard), [changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount), and [writeObjects](https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:)) documentation.
