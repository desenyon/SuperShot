# SuperShot

SuperShot is a native macOS screenshot app whose first requirement is that it is beautiful. It captures (screen, window, area, scrolling), recognizes (text, QR), beautifies (backgrounds, shadows, padding), and edits (a full annotation editor with AI tools). Everything runs locally and fast.

This file is the product specification and the rules for agents working here. Native implementation lives in `Sources/` and automated checks in `Tests/`. A signed local build can be staged with `scripts/bundle.sh`. See `README.md` for usage, `CHANGELOG.md` for release history, and `docs/previews/` for offscreen renders. Features listed here describe the target specification and require separate acceptance evidence.

## Product principles

1. **Beauty is a feature with acceptance criteria.** A screen that works but looks ordinary is not done. See "Design language".
2. **Capture is instant.** Hotkey to frozen overlay in under 100 ms. Never show a spinner between pressing a hotkey and selecting.
3. **Local first.** Capture, recording, recognition, Library organization, and editing run on-device. A user action initiates a webpage load, update check, Ask request, or Review Link upload. Ask and Review Links identify the destination before the first send.
4. **Non-destructive.** The original pixels are never modified. Annotations, crop, and backdrop are layers that can be reopened and changed later.
5. **Everything has a hotkey**, and every hotkey can be changed.

## Platform and stack

| Decision | Choice | Why |
|---|---|---|
| Platform | macOS only, deployment target macOS 26 | Liquid Glass materials and current ScreenCaptureKit |
| Language | Swift 6, strict concurrency on | |
| UI | AppKit for windows, overlays, canvas, and event handling; SwiftUI for settings, panels, and inspectors | Overlays and the canvas need exact control of windows and events |
| Capture | ScreenCaptureKit | CGWindowList capture is deprecated |
| Rendering | Core Graphics for vector annotations, Core Image + Metal for blur, spotlight, magnifier, backdrop | Live effects at 60 fps on 5K captures |
| Recognition | Apple Vision | See "Recognition" |
| Build | Swift Package Manager plus a script that assembles the `.app` | This machine has Command Line Tools only, no Xcode. The package must still open cleanly in Xcode |
| Dependencies | None by default | Adding one needs a stated reason in the PR |

No Electron, no web views, no cross-platform UI layers.

## Features

### Capture modes

- **Fullscreen**: the display under the cursor, or all displays.
- **Window**: hover to highlight, click to capture. Shadow can be kept, trimmed, or replaced by SuperShot's own shadow.
- **Area**: frozen-screen overlay with crosshair, live dimensions, a pixel loupe, snapping to window edges, arrow-key nudging, space to move the selection, shift to lock the axis, and typed exact sizes. Remembers the last area ("capture previous area").
- **Scrolling**: select an area, then scroll. Frames are stitched live with a growing preview. Manual scrolling is the default; auto-scroll (synthetic scroll events, needs Accessibility permission) is optional. Vertical first, horizontal later.
- **Timed**: 3, 5, or 10 second delay, for menus and hover states.
- **Recognize text**: select an area, text goes straight to the clipboard, no image is kept.
- **Scan QR / barcode**: select an area, show the payload with open and copy actions.
- **Disposable area**: retain the screenshot for this session without writing a Library project. The thumbnail and Recent Captures let users keep it explicitly.
- **Webpage**: capture a URL in an installed Chromium browser with a fresh headless profile, custom CSS viewport, light or dark appearance, and optional full-page height.

### After capture

The user configures a **set** of actions that all run after a capture (and/or, any combination):

- Show the quick-access thumbnail
- Copy to clipboard
- Save to the default folder
- Open the editor
- Pin to screen

Area capture has its own separate setting, a single choice: **open editor**, **show thumbnail**, or **copy**. Each capture mode may override the global set.

Settings → Capture → After capture includes **Always copy**, an additive switch that copies alongside mode overrides and explicit overlay actions. **Area selection → Capture on mouse release** skips Return for a freshly dragged area screenshot and defaults off. Clicks, zero-area drags, and cancellation must never capture. Window, scrolling, OCR, and barcode selection retain their existing confirmation behavior. Typed selections and subsequent resize or move operations can still be confirmed with Return.

The **quick-access thumbnail** floats in a screen corner. Drag it into an app, click to edit, or swipe to dismiss. Its action shelf sits below the image. Several thumbnails stack and Recent Captures retains a bounded list for this session.

### Backdrop

Applied in the editor, or automatically after capture if the user enables it.

- **Fill**: none (transparent), solid color, gradient, wallpaper (the current desktop wallpaper, bundled wallpapers, or the user's own image), or a blurred version of any of these.
- **Layout**: padding, inset, auto-balance (evens out uneven margins around the content), corner radius, shadow strength, alignment in a 3×3 grid, and aspect ratio (auto, 16:9, 4:3, 1:1, social presets, custom).
- **Shadow trimming**: remove the system window shadow, and trim transparent edges.
- Backdrop presets can be saved, named, and bound to a hotkey.

### Editor

Opens on a capture, on any image file, or on a pasted image.

**Tools**

| Group | Tools |
|---|---|
| Pointer | Select (move, resize, rotate, multi-select, reorder), crop |
| Shapes | Rectangle, oval, line, arrow (straight, curved, several head styles) |
| Marking | Freehand drawing with smoothing, highlighter, counter (auto-incrementing numbered badges), text (with fill and outline styles) |
| Focus | Spotlight (dims everything outside a region), magnifier (a zoomed callout), backdrop |
| Hiding | Blur, pixelate, erase (fills with the surrounding color or content) |
| Measuring | Ruler (pixel distances and angles, in pixels or points), color picker (hex, RGB, HSL, P3; copies on click) |
| Content | Paste image as a layer, drop images in |

Each tool has a small set of options (color, stroke width, style, opacity) and remembers them per tool.

**Actions**: copy, save, save as, pin, share, and a drag handle that drags the finished image into any app.

**Info panel**: pixel size, point size, scale factor (1x/2x), file size per format, color profile, capture date, source app and window title, display, and position on screen.

**Canvas**: zoom from 10% to 3200%, pinch and scroll zoom, zoom to fit, zoom to selection, a pixel grid above 800%, and unlimited undo and redo.

**AI tools** (see "AI tools" for how they run)

- Smart redact: finds emails, phone numbers, API keys, card numbers, faces, and addresses, and proposes blurs the user accepts or rejects
- Remove background or lift the subject
- Object erase with content-aware fill
- Upscale
- Copy text, copy as Markdown, extract a table as CSV, extract code
- Describe the image (alt text) and suggest a file name
- Auto-annotate from a prompt ("point an arrow at the Save button")
- Translate text in place

### Pins

A pinned screenshot is a borderless, always-on-top window. Drag the image to move it; drag any edge or corner to resize with its aspect preserved. Double-click restores the initial size. Arrow keys move a focused pin; +/− resize, and 0 resets size. It has opacity controls, a click-through lock, and copy/close actions. A locked pin shows how to unlock it on hover; holding the unlock key (Option by default, Settings → Pins & previews) over it makes it clickable and turns its badge into an Unlock button. Unlock All Pins is in the menu bar menu. Settings → Pins & previews configures new-pin size, opacity, shadow, and Space visibility, plus thumbnail corner, width, and dismissal delay.

### Hotkeys

- Global hotkeys for every capture mode, capture previous area, open last capture in the editor, open history, pin from clipboard, recognize text, scan QR, and toggle desktop icons.
- Single-key tool shortcuts inside the editor (for example `A` arrow, `R` rectangle, `T` text, `B` blur), all editable.
- A recorder control for assigning shortcuts, with conflict detection against SuperShot's own bindings and system shortcuts.
- Modifier behavior during area selection is also configurable.
- Importable and exportable shortcut profiles, plus a "replace the system screenshot keys" preset. That preset needs the user to turn off the system shortcuts in System Settings; the app walks them through it.
- Registered with Carbon `RegisterEventHotKey`, which needs no Accessibility permission.

### Saving and formats

- **Formats**: PNG, JPEG, HEIC, TIFF, PDF, plus WebP and AVIF where the system can encode them. Build the list at runtime from `CGImageDestinationCopyTypeIdentifiers` rather than hardcoding it.
- Per-format quality, and a separate choice of format for clipboard versus file.
- Retina handling: keep 2x, or downscale to 1x.
- Color: keep the display profile, or convert to sRGB.
- File name templates with tokens (date, time, app, window title, counter, size).
- Default folder, with optional subfolders by date or by app.
- Optional sidecar project file (`.supershot`) holding the original and all layers, so a saved capture can be reopened and edited.
- **History**: a searchable library of recent captures. OCR text is indexed, so captures can be found by the words in them. Retention is configurable.

### Recognition

Use Apple Vision: `RecognizeTextRequest` for text and `DetectBarcodesRequest` for QR and barcodes. It runs on-device, supports many languages, and needs no bundled custom model. Measure latency, including first-use model compilation, instead of promising a fixed completion time. Set the minimum text-height fraction for screenshot-sized UI text; Vision's default excludes small text on large displays. Do not ship a custom OCR or embedding model unless Vision measurably fails on a real case.

Recognition runs in the background on every capture, which makes these possible without waiting: select and copy text directly from the image in the editor, click detected links and QR codes, search history by text, and smart redact.

### AI tools

All AI features sit behind one `AIProvider` protocol with three tiers. Use the lowest tier that can do the job.

1. **Vision and Core Image** (always available): OCR, barcodes, faces, subject lifting, redaction detection with `NSDataDetector` and patterns.
2. **On-device models** (downloaded on demand, never bundled): inpainting for object erase, upscaling, and Apple's Foundation Models framework for naming, describing, and Markdown conversion where available.
3. **Subscription CLI** (off until the user signs in): public builds use Codex (ChatGPT) on this Mac. The Claude Code transport is compiled into local debug builds only. The confirmation setting identifies the upload destination before the first send.

### Ask (chat about a capture)

Ask opens from the editor, the area-selection action bar, the quick-access thumbnail, and an edited still in the recording editor. Public builds use the user's ChatGPT subscription via `codex app-server`. Codex owns sign-in and credentials. The public API is `AI/Assistant/AssistantTypes.swift`. Before the first upload in a conversation the panel shows the destination when confirmation is enabled. Recognized text may be included and Smart Redact can blur sensitive regions first. Conversations are read-only and never run tools. OpenAI documents continued use of [app-server authentication for existing local integrations](https://learn.chatgpt.com/docs/app-server#authentication). Anthropic's [authentication policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) restricts using subscriptions in third-party products. Public builds omit that transport. A saved Claude selection resolves to Off until the user picks ChatGPT.

### System integration

- Menu bar app with no Dock icon by default (optional Dock icon).
- Launch at login through `SMAppService.mainApp`.
- Hide desktop icons during capture (optional).
- Capture sound, cursor inclusion, and overlay behavior are all settings.
- URL scheme and App Intents so Shortcuts and scripts can trigger any capture mode.

## Design language

`docs/inspiration/editor-reference.png` shows the **layout** to start from: tools along the top, backdrop controls on the left, canvas in the center, zoom and export actions along the bottom. The user's verdict on it is that it is too basic. Keep the structure, and make the execution far better. Do not copy its visual style.

What "better" means here:

- **The screenshot is the hero.** Chrome recedes. The canvas is edge to edge, and toolbars and panels float over it as glass, not as opaque bars that box it in.
- **Floating glass surfaces.** The tool palette is a floating capsule, the inspector a floating panel with generous corner radius. Use the system Liquid Glass materials so the app belongs on macOS 26, and never fake them with flat translucent gray. Use `GlassSurface(radius:tint:interactive:)` for every glass piece (tinted for a primary control, interactive for things the pointer acts on) and wrap neighbouring pieces in `GlassGroup` so they merge. Check glass with `--live-preview` from the signed bundle, which captures real windows with ScreenCaptureKit; offscreen previews only show the opaque fallback.
- **Editor layout as built**: a centered tool capsule at the top with a contextual options bar under it (shown only when a tool or selection has options), the backdrop panel floating on the left, one switchable panel on the right (text and codes, smart tools, Ask, layers, details), and three capsules along the bottom (document and undo, zoom, export).
- **Customization** lives in `Preferences.customization` (accent, density, glass or solid chrome, editor tool order and visibility, area-selection action bar buttons and labels, thumbnail hover buttons) and `Preferences.assistant`. New fields decode optionally.
- **One accent color** (`DS.accent`, Clear blue `#2F7CF6` by default; the user may pick blue, teal, graphite, or tangerine in Settings → Appearance), used only for selection and primary actions. Everything else is neutral. Annotation colors are the only saturated color on screen. **No purple, violet, or indigo anywhere** in the app: not in accents, palettes, gradients, presets, or the brand mark. `IconTests` enforces this for the shared palettes. Read the accent through `DS.accent`/`DS.nsAccent`/`DS.onAccent` (MainActor, live); AppKit views redraw on `DS.themeDidChange`.
- **Settings uses an edge-to-edge electric-blue glass rail and a neutral detail pane.** All nine pages share `DS.Preferences` and the Settings components. The glass rail has six icon-only quick destinations, collapsible grouped navigation, and search. The detail pane uses plain section headings, dividers, and neutral controls. Reduce Transparency uses solid appearance-specific surfaces.
- **Typography**: SF Pro, with SF Mono for numbers (dimensions, zoom, hex values) using tabular figures. Three text sizes at most per surface.
- **Icons**: Phosphor Icons 2.1.1 (MIT, `THIRD_PARTY_NOTICES.md`), embedded as SVG in `DesignSystem/PhosphorData.swift` and drawn through `Icon(name, weight:size:)` in SwiftUI or `Icons.image`/`Icons.tinted` in AppKit. Regular weight at rest, `.fill` for selected or active states, `.bold` only on small dark HUDs. Pass Phosphor names (`"push-pin"`); older SF Symbol names resolve through `Icons.legacy`. To add icons, append names to `scripts/make-icons.swift` and rerun it. Never use `Image(systemName:)` or `NSImage(systemSymbolName:)` in feature code, except native menu checkmarks. No mixed icon styles.
- **Controls are custom where the default is ugly.** Sliders show their value while dragged, swatches are large and show a selection ring, the alignment grid and ratio picker are purpose-built. No default gray bezel buttons.
- **Live previews instead of labels.** Backdrop presets are thumbnails of the actual capture with that backdrop applied. Tool style pickers show the real stroke.
- **Motion everywhere, with one physical feel.** Every animation comes from `DS.Motion` (`Sources/DesignSystem/Motion.swift`): `snappy` (selection tiles, tool switch, toggles), `panel` (panels, popovers, page changes), `arrive` (thumbnails, chat messages, the area action bar, toasts), `gentle` (crossfades, backdrop and value changes), `hover`; transitions `reveal(from:)`, `pop`, `rise`; `stagger` for lists and grids; `PressableStyle`, `.hoverLift()`, `.staggeredAppear(_:)`; `present`/`dismiss`/`caSpring` for AppKit windows and layers. Springs are interruptible and retarget mid-flight. Selection indicators slide between items with `matchedGeometryEffect` rather than jumping. Nothing that appears or disappears just pops in. Under Reduce Motion, movement becomes short crossfades. No literal animation curves in feature code.
- **Progressive disclosure.** Tool options appear near the selection as a small contextual bar. Panels the user is not using stay hidden.
- **The capture overlay is part of the design.** Crosshair, dimension badge, loupe, and selection handles get the same care as the editor.
- Settings and setup use compact neutral grouped surfaces, Phosphor icons on neutral tiles, restrained selection accents, and no decorative gradients or glow. The 2026-11-16 panel reference supplies density and hierarchy, not copied assets.
- **The logo** is defined once in `DesignSystem/Brand.swift`: a white rounded viewfinder on a Clear-blue tile. The app icon (`--render-app-icon`, used by `scripts/bundle.sh`), the menu bar template, `BrandIcon`, and `BrandMark` all draw from it. Never draw the logo anywhere else.
- Dark and light appearance both designed, not derived. Full keyboard access and VoiceOver labels on every control.

Every UI change must be checked by running the app and looking at it, in both appearances. Screenshots of new surfaces go in the PR. Use an isolated macOS desktop or a user-authorized interactive session for these checks; otherwise record visual verification as pending.

## Architecture

One Swift package. Each module is a library target with its own tests; only `SuperShotApp` knows about all of them.

| Module | Responsibility |
|---|---|
| `SuperShotApp` | App lifecycle, menu bar, windows, wiring |
| `Capture` | ScreenCaptureKit sessions, overlay windows, area selection, window picking, scrolling capture and stitching |
| `Document` | The capture document model: base image, layers, crop, backdrop, undo, `.supershot` file format. No UI imports |
| `Render` | Turns a `Document` into pixels. The same code path draws the canvas and exports files |
| `Editor` | Canvas view, tools, selection, inspector, info panel |
| `Recognition` | Vision wrappers, OCR index |
| `AI` | `AIProvider` protocol and the three tiers |
| `Hotkeys` | Global registration, recorder control, conflict detection, profiles |
| `Library` | History store, thumbnails, search, retention |
| `Export` | Encoders, file naming, clipboard, drag and drop |
| `Settings` | Typed settings store and the settings UI |
| `DesignSystem` | Colors, type, materials, motion constants, shared controls |

Rules:

- `Document` and `Render` have no AppKit or SwiftUI view code. They must be testable headless.
- Every tool is one type conforming to a `Tool` protocol and produces one `Layer` type. Adding a tool must not require editing the canvas.
- Export output and on-screen canvas come from the same renderer. If they can differ, it is a bug.
- UI code is `@MainActor`. Capture, stitching, encoding, and recognition run off the main actor.
- All colors, radii, spacing, and animation curves come from `DesignSystem`. No literal values in feature code.
- Sliders preview with `EditorModel.previewChange` while dragging and call `commitDraft` on release, so one drag is one undo step.
- Editor responsiveness rests on three rules. Keep them when changing the editor:
  - The rendered document is shown in a `CALayer`; panning and zooming move that layer and never re-render.
  - Selected layers and the layer being drawn are left out of the raster (`EditorModel.rasterExcluded`) and painted by the canvas overlay through `DocumentRenderer.drawLive`, so moving, resizing, and restyling them costs no render. Blur, pixelate, and magnifier sample pixels beneath them and stay in the raster.
  - `EditorModel.refresh` never cancels a render in progress. Requests made meanwhile collapse into one follow-up and every finished frame is shown. Cancelling on each change is what once made controls update only after the pointer stopped.
- `PREVIEW_BENCH=1` with the `--render-previews` arguments prints editor frame costs on a 5K capture. Run it after renderer or editor changes.
- New `Backdrop` fields must be optional so older `.supershot` projects and saved preferences still decode.

## Permissions

- **Screen Recording** is required for screenshots and local screen recording. On first launch without access, setup offers optional practice on a sample before the permission prompt. A separate persistent flag records that setup was shown, even if it was closed. Returning users manage access in Settings → Privacy and can open Welcome Tour from Help. Permission revocation must never reopen the welcome page.
- **Microphone and camera** access are requested only for enabled recording inputs when the user starts recording. Review Links use rendered media and explicit destination consent.
- **Accessibility** is requested only when the user enables auto-scroll.
- Development builds must be signed with a stable local signing identity. Ad-hoc signing changes the code identity on every build, which makes macOS forget the Screen Recording grant each time.
- Recent macOS versions periodically re-prompt for apps that capture the screen directly. Confirm the current behavior on macOS 26 and 27 before designing around it.

## Milestones

1. **Skeleton**: package, app bundle script, signing, menu bar app, permission onboarding, `DesignSystem` base.
2. **Capture core**: fullscreen, window, and area capture, the overlay, global hotkeys, after-capture actions, quick-access thumbnail, save and copy.
3. **Editor core**: document model, renderer, canvas, select, crop, shapes, arrow, text, drawing, undo, export.
4. **Backdrop**: fills, layout controls, shadow trimming, presets.
5. **Editor complete**: blur, erase, highlighter, spotlight, counter, magnifier, ruler, color picker, paste image, info panel, pins.
6. **Recognition**: OCR, QR, live text in the editor, history with search.
7. **Scrolling capture.**
8. **AI tools**: tier 1, then tier 2, then tier 3.
9. **Polish**: settings completeness, hotkey profiles, launch at login, Shortcuts, performance pass.

Finish and polish each milestone before starting the next. A milestone is done when it works, looks finished in both appearances, and has tests.

## Releases

- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, add a `CHANGELOG.md` entry, write a verification report in `docs/verification/`, run `scripts/test-background.sh`, `scripts/preview.sh`, and the `PREVIEW_BENCH` comparison, then `scripts/bundle.sh`. Release archives are `SuperShot-<version>-macOS-arm64.zip` (made with `ditto -c -k --keepParent`) plus `SHA256SUMS.txt`, attached to a GitHub release whose notes list every change from the changelog.

## Working rules for agents

- Commands: `swift build`; `scripts/test.sh` for the full Swift Testing suite; `scripts/bundle.sh` to produce and stably sign an optimized release at `dist/SuperShot.app` (use `BUNDLE_OUTPUT_DIR="$PWD/dist/Updated"` to stage without replacing a running app); `scripts/benchmark.sh` for synthetic release-build renderer and OCR measurements. The test wrapper loads the Testing macro plugin required by this machine's Command Line Tools. `scripts/setup-signing.sh` provisions a local development identity on a new checkout; never commit `.local-signing/`.
- Live Ask tests (`LiveAssistantTests`, `LiveAskModelTests`) run real turns through the signed-in Codex (and Claude Code with `SUPERSHOT_LIVE_CLAUDE=1`). They are skipped unless `SUPERSHOT_LIVE_ASK=1`, spend the user's plan, and never belong in the background suite. Run them after any change to `AI/Assistant` or the Ask model.
- Default to background verification while the user works: `scripts/test-background.sh` runs offscreen tests at reduced CPU priority with two build jobs and excludes the AppKit recorder-window test. Keep its exclusions current when adding desktop-dependent tests. Detached-view event tests and named, isolated pasteboard tests are allowed; they must never post global input or write to the shared clipboard.
- Do not activate or launch GUI apps, switch tabs or windows, send keyboard/mouse input, change the shared clipboard, trigger capture overlays or permission prompts, or quit/replace the user's running app during background verification. The user explicitly requested uninterrupted desktop use. Resume interactive desktop testing only when the user asks for it or an isolated macOS environment is available.
- `scripts/preview.sh` renders every main surface (editor states, capture overlay, settings pages, welcome, library, thumbnail, pin, panels) to `docs/previews/` in dark and light, offscreen, without showing a window. Run it after any UI change and look at the PNGs. Add a scene to `PreviewRenderer` for each new surface. System glass cannot render offscreen, so `GlassSurface` draws its opaque fallback there; real Liquid Glass still needs an interactive check.
- Verify UI work by running the app in an isolated macOS desktop or a user-authorized interactive session. A passing build or offscreen test does not verify appearance, actual screen capture, or OS integration. If no isolated environment is available, leave those checks pending and continue background work.
- Verify any Apple API named in this file against current documentation before relying on it. Several are recent and their details may differ from what is written here.
- Performance budgets: hotkey to overlay under 100 ms, capture to thumbnail under 200 ms, OCR on a full display under 300 ms, canvas at 60 fps with 200 layers on a 5K image. Measure before claiming.
- Test `Document`, `Render`, stitching, file naming, and hotkey conflict logic with unit tests. Renderer changes get image snapshot tests.
- Do not add dependencies, telemetry, or network calls without asking.
- Do not copy the look, name, or assets of existing screenshot apps.
- Keep this file current. When a decision here changes, change it here in the same PR.

## Open questions

- App Store distribution or direct download? Direct download with notarization is assumed, since sandboxing limits some capture and auto-scroll behavior.
- Should SuperShot offer a managed Review Links service alongside the optional self-hosted endpoint?
- More inspiration images are welcome in `docs/inspiration/`; only one arrived.
