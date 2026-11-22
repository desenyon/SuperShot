# Glass and feature audit · 2026-11-21

Scope includes all nine Settings pages, the screenshot workflow, Capture Webpage, pins, and the recording workflow through export and Ask. The Settings reference informed the full-height electric-blue rail, six icon-only destinations, selected row, and bottom utilities. The content area uses plain headings and dividers. Offscreen images show the glass fallback.

## Settings

| Page | Behavior reviewed | Verification |
|---|---|---|
| General | Launch at login, Dock visibility, capture summaries, navigation links | Light and dark renders, Settings tests, OS approval remains a live check |
| Capture | Area defaults, per-mode actions, immediate capture, always-copy, cursor and timed controls, links to webpage and recording | Preference and detached-overlay tests, normal and narrow renders |
| Pins & previews | Thumbnail placement, width, dismissal, pin size, opacity, shadow, Spaces, unlock modifier | Preference fixtures, pin geometry tests, dark and light lock states |
| Output | Folder selection and preview, formats and quality, 1×, profile, file tokens, linked exports | Format and filename tests, long-path and narrow renders |
| Library | Retention, metadata and suggestions, model availability, direct Library link | Library and organizer tests, offscreen Settings and Library renders |
| Shortcuts | Recorder feedback, per-action conflicts, profiles, system screenshot preset, new URL entry points | Profile and registration tests, detached bridge tests, narrow and long renders |
| Appearance | System, light and dark, accent, density, solid/glass, toolbar and action customization | Theme and icon tests, standard, customization, and accessibility variants |
| Privacy | Screen permission status and recovery, input permissions, upload destinations | Injected permission tests and denied render. System dialogs remain a live check |
| Assistant | Provider choice, account status, models, recognized text, redaction, consent, and local chat retention | Ready, signed-out, missing-CLI renders and scripted Ask tests |

Sidebar previews cover expanded, collapsed, search, narrow window, and Reduce Transparency. Content scrolls independently of navigation. Entries and quick destinations are keyboard-addressable and display the selected state.

## Results

- The final background suite passed 198 tests. Eight opt-in cases were skipped in that default run.
- A separate opt-in run passed five Chromium loopback cases and three signed-in Ask cases, including Codex and Claude follow-ups on synthetic images. Recording-specific tests use generated video and verify the edited frame before it reaches the shared Ask panel.
- All six Review Links loopback tests passed.
- The icon audit resolved all 126 literal calls. The Swift tests also check the new recording glyphs in regular, fill, and bold weights.
- Generated and checked 220 PNGs across 110 dark and light appearance pairs. The visual pass includes all nine Settings pages, the webpage capture states, pins and overlays, each recording tool, and narrow editor layouts. The narrow recording rail switches to icon-only buttons so all five tools remain visible.
- One synthetic 5K editor benchmark from the signed release build measured 14.3 ms for a 1,280-pixel drag preview, 73.9 ms for a 2,200-pixel idle preview, 688.9 ms for a full-resolution export, and 0.5 ms to paint 40 live layers. These are diagnostic timings from one run.

## Capture, editing, and delivery

| Workflow | Behavior reviewed | Verification |
|---|---|---|
| Menu, onboarding, and URLs | Welcome practice and explicit first capture, menu routing, URL modes and delays | Onboarding and URL command tests; practice, access, and recovery previews |
| Display, window, area, text, and code | Selection, resize, immediate mode, cancellation, previous image area, recognition, window metadata | Selection/event and Vision fixtures, generated overlays and code-results panel. Live ScreenCaptureKit capture and Finder exclusion remain open |
| Scrolling | Stitching, auto-scroll status, overlap recovery and finish with partial frames | Generated stitch cases, panel and recovery previews. Accessibility events remain a live check |
| Quick access and pins | Thumbnail actions use current edited pixels, free movement and resizing, click-through lock, keyboard controls | Current-document path reviewed across copy, save, pin, and drag. Geometry tests include offset displays and keeping a pin reachable. Actual pointer, clipboard, Spaces, and drop targets remain open |
| Screenshot editor | Backdrop presets, annotate and select, inspect, recognize, smart tools, Ask, copy, save, drag and share | Document, renderer, export, editor, and scripted Ask tests. Source review plus viewport, tool and inspector previews |
| Library and Recent Captures | Search, date groups, metadata, suggestions, reminders, edited-image copy, keep and retention | Library and Recent model tests, gallery, details, and empty previews |
| Capture Webpage | URL normalization, presets, custom size, appearance, full page versus viewport, cancel, error and retry | Headless Chromium fixtures verify CSS breakpoints, appearance, deferred footer, URL anchors, stalled assets, and cookie isolation. Form tests cover invalid input, missing browser recovery, and stale cancellation |
| Review Links and updates | Edited image and video sharing, recipient consent, upload and revoke, release feedback | Six loopback service checks, share/update previews. External deployment and real GitHub UI remain open |

## Recording

| Stage | Behavior reviewed | Verification |
|---|---|---|
| Setup | Display arrangement, window and area choices, explicit preview, resolution, frame cadence, countdown, selected inputs | Source geometry tests for offset displays and pixel scaling; standard, narrow, window, area, preview, and missing-permission renders |
| Active | Timer, selected source, stop, finish, partial-file recovery | Source and lifecycle review; offscreen HUD, no capture of a real desktop |
| Edit | Filmstrip, trim, cuts, playhead, frame step, zoom, undo/redo, audio controls | Synthetic recording and composition tests, plus editor previews with a narrow tool rail beside the video |
| Annotate | Timed arrow, rectangle, text, spotlight, highlight, blur, and opaque cover | Pixel assertions for timed edits and MP4/GIF output |
| Camera | Hidden, corner, circle, side-by-side, stacked, camera-only and timed layout changes | Synthetic camera and screen tracks exercise crop, alignment, all visible layouts, and export after cuts |
| Transcript | On-device transcription, caption styles, cut by selected transcript, filler/pause edits, text/SRT/WebVTT | Transcript edit and subtitle timing tests, transcript panel previews. Speech asset download and actual microphone input remain open |
| Ask | Pause at an edited frame, prepare a local still, select an optional region, provider consent, replace the frame explicitly | Generated movie tests verify cut timing, privacy covers, replacement and consent. Scripted provider in the offscreen recording panel |
| Export and Library | Edited MP4 and GIF, preview thumbnails, file protection, reopen and share | Synthetic export and preservation tests; populated and empty Recordings views |

The existing app session was not used for interactive testing. Real WindowServer Liquid Glass, hardware camera and microphone, display changes and Spaces, global hotkeys, and native Shortcuts metadata need an isolated macOS desktop or an authorized live session. The locally staged bundle uses the development signature.

Apple documentation consulted for the [window frame override](https://developer.apple.com/documentation/appkit/nswindow/constrainframerect%28_%3Ato%3A%29) and [native intent parameters](https://developer.apple.com/documentation/appintents/adding-parameters-to-an-app-intent).
