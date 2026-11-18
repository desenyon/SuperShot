# Changelog

All notable changes to SuperShot. Versions follow `CFBundleShortVersionString`; build numbers follow `CFBundleVersion`.

## 0.1.1 (build 8) · 2026-11-18

### Fixed

- **Ask with ChatGPT failed on every question** when your Codex config defined MCP servers. SuperShot launched Codex with `-c mcp_servers={}` to switch them off, but Codex merges `-c` overrides into your config rather than replacing it, so the servers still started and SuperShot's safety check refused to send. Ask now reads your configured servers with `config/read` and disables each one for the conversation's own thread. Your Codex config is never written. The safety check still refuses to send if any server is live or exposes tools, and accepts servers Codex reports as `disabled`.
- Codex exits when asked to disable a feature it does not know. SuperShot now reads `codex features list` and disables only features your installed version has, so other Codex versions start cleanly.
- The Ask header's provider pill lost its capsule and dropdown caret; it is a proper menu again.

### Ask

- **Solve, Explain, Suggest, Improve** sit above the typing bar. Each has its own icon and a full prompt; one tap asks right away and includes anything you already typed. Your bubble shows the action's name and your note instead of the whole prompt. Cancelling the upload confirmation puts back only what you typed.
- A "What would you like to know?" prompt in empty conversations, and a "looking at your capture…" indicator with animated dots until the first words arrive.
- The provider pill switches between ChatGPT and Claude.
- Suggestion lists left at 0.1.0's defaults change to the four new actions automatically. Custom suggestions are kept and still work.

### Liquid Glass

- **The bar after you select an area is real Liquid Glass.** Capture is its own accent glass button beside a glass group holding Copy, Save, Edit, Pin, Text, and Ask; the pieces refract the frozen screen and merge like a macOS toolbar. Cells fill their icon and gain a soft wash on hover, and the bar springs in when a selection finishes.
- The quick-access thumbnail's hover bar and its size tag are glass, with hover washes and an accent Ask button while its chat is open.
- `GlassSurface` gained accent-tinted and interactive variants, and `GlassGroup` blends neighboring glass shapes. Tinted glass carries a solid tint layer so primary controls stay legible on any background. Solid chrome, Reduce Transparency, and offscreen renders keep their opaque fallback.

### Pins

- **Unlocking a pin no longer needs the menu bar.** Hover a locked pin and a glass badge says "Hold ⌥ to unlock". Hold the key and the pin accepts clicks; the badge becomes an accent **Unlock** button. Release the key and clicks pass through again. Unlock All Pins remains in the menu.
- Settings → Pins & previews → Click-through lock chooses the unlock key: Option, Command, Control, or Shift.
- The watch uses no extra permission: it reads the pointer and modifier keys only while a pin is locked, about 15 times a second, and re-renders a pin only when its state changes.

### Design

- The menu bar logo is smaller: the glyph spans about 13 pt of its 18 pt slot, with a slightly heavier stroke for crispness.
- New Phosphor icons for the quick actions: wrench, book, lightbulb, and trend-up.

### Verification and tooling

- `SuperShot --live-preview <dir> <fixture>` (from the signed bundle) shows chosen surfaces in real windows for about a second each and captures them with ScreenCaptureKit, so Liquid Glass can be checked; offscreen previews cannot render glass. Captures of this release are in `docs/verification/0.1.1-glass/`.
- Opt-in live tests run real Ask turns through the signed-in Codex: `SUPERSHOT_LIVE_ASK=1 scripts/test.sh --filter Live` (add `SUPERSHOT_LIVE_CLAUDE=1` for Claude Code). They passed for this release and are skipped in normal runs.
- 127 background tests across 11 targets (up from 119), with new coverage for the MCP fix, feature-flag parsing, quick actions, suggestion migration, and the pin unlock preference.

## 0.1.0 (build 7) · 2026-11-18

### New: Ask about a capture

- **Ask** chats about the current screenshot using your own ChatGPT or Claude plan. No API keys: SuperShot drives the Codex CLI (`codex app-server`, the default) or Claude Code (`claude -p`, stream-json) installed on your Mac, and each tool owns its own sign-in.
- Three entry points: an **Ask** tab in the editor's right panel, an **Ask** button on the area-selection bar (captures, then opens the chat), and an **Ask** button on the quick-access thumbnail that opens a glass chat panel attached to it. **Open in editor** carries the conversation, draft, and any reply in progress.
- Attach a region of the image to a question; replies stream in with a Stop button; each reply offers **Copy**, **Add as text** (an editable text layer), and **Show on image** (outlines the matching recognized text).
- Before the first upload in a conversation, Ask names who receives the image. **Hide it, then send** blurs sensitive regions found by Smart redact and removes sensitive text from what is sent.
- In-panel states for not installed, signed out (with browser or Terminal sign-in), waiting for sign-in, usage limit reached (with "Ask Claude instead"), and errors with Retry. Plan usage appears in the footer when the tool reports it.
- Conversations can be kept with their capture in History: restored when the capture reopens, searchable in the Library, deleted with the capture, and purged when the setting is turned off.
- Safety: Codex threads are ephemeral, read-only, network-off, and never run commands; approval requests are always declined; plugins, hooks, MCP servers, and shell tools are disabled, and a turn is refused if any MCP server is active. Claude Code runs with no tools, no saved settings, no MCP servers, no session persistence, and safe mode. Screenshots are downscaled to 2000 px and written only to a private temporary folder that is removed when the conversation closes.

### New: Settings → Assistant and Settings → Appearance

- **Assistant:** choose ChatGPT, Claude, or Off (with detected tool versions); sign in and out; see plan usage and reset day; pick a model; confirm before sending; include recognized text; hide sensitive details first; keep conversations; edit suggestion chips; install hints when a tool is missing.
- **Appearance:** System/Light/Dark; accent (Blue, Teal, Graphite, Tangerine); compact or regular density; glass or solid floating chrome; drag-to-reorder and show/hide for editor tools, area-selection buttons (with an option to hide labels), and thumbnail buttons, each with a live preview strip and Reset.

### Design

- **New logo:** a bold white rounded viewfinder on a Clear-blue gradient tile. The app icon, menu bar item, Settings sidebar, and Welcome window all draw it from one definition, and the bundle's `.icns` is rendered from the same code.
- **No purple anywhere.** The indigo accent is replaced by Clear blue `#2F7CF6`. Purple was removed from annotation colors (now cyan), backdrop swatches, and gradients (Iris → Lagoon, Grape → Forest, Candy → Peach, and Ember's purple stop). Tests fail if a shared palette or the logo turns purple.
- **New icon set:** Phosphor Icons 2.1.1 (MIT) replace SF Symbols throughout, embedded as SVG so they render identically in menus, AppKit drawing, and offscreen previews. Regular weight at rest, fill weight for selected tools. Smart tools now use a magic wand.
- **Motion everywhere** through one system (`DS.Motion`): sliding selection tiles in the tool palette, panel switcher, Settings sidebar, segmented controls, and swatches; panels and the options bar reveal with springs; thumbnails and the Ask panel spring in and out; chat messages rise into place and streamed text grows smoothly; backdrop changes crossfade on the canvas; zoom buttons animate the canvas; pins present and dismiss; Library cards stagger in and lift on hover; the countdown rolls its digits. Every animation reduces to a short crossfade under Reduce Motion.
- **Settings redesign:** grouped sidebar sections with neutral icon tiles and a sliding selection, large page titles, 12 pt card groups, comfortable rows, animated page changes, and a permission and version status card. All nine pages fit at the minimum window size. Graphite-only styling is kept.
- **Editor polish:** all default tools fit at the minimum width; the options bar keeps labels beside their values; gradient tiles show their colors; the full ratio grid, alignment control, Trim, and Presets fit without clipping; bottom capsules share one height; zoom shows the real percentage with a menu; Save is a split button with its format; Drag has a grip. Copy and Save show a checkmark only after the write succeeds, and a warning with a brief shake if it fails.
- **Area-selection bar:** redesigned dark glass HUD with larger cells, a filled accent Capture button, hover and press states, an Ask button, and configurable order and labels.
- **Pins:** a glass hover capsule with opacity slider, copy, lock, and close; locked pins show a closed lock; the resize affordance recedes when idle.
- **Library:** larger thumbnails with source app icons, dates, and dimensions; All / Today / This week filters; better empty states. Search also matches kept Ask conversations.
- **Welcome:** modern layout with the new logo and a staged entrance.

### Fixes

- The backdrop panel no longer clips its ratio grid and footer.
- "Opacity" no longer wraps in the options bar; the minimum-width editor no longer scrolls its tool palette.
- The "Capture" label no longer touches its button edge on the area-selection bar.
- Copy and Save no longer report success before the clipboard or file write finishes.

### Under the hood

- New `AI/Assistant` API (`AssistantService`, `AssistantConversation`) with Codex app-server (JSON-RPC) and Claude Code (stream-json) implementations, a CLI locator with version gating, and a line-based process transport.
- `Preferences.assistant` and `Preferences.customization` decode optionally, so 0.0.1 preferences carry over unchanged.
- `scripts/make-icons.swift` regenerates the embedded icon set; `scripts/bundle.sh` renders the app icon through the app binary (`--render-app-icon`).
- 119 background tests across 11 targets (up from 76), including fake-CLI end-to-end tests for both Ask backends.

### Known limits

- Built and signed with a stable local development identity; not notarized.
- Verified offscreen only. Live Liquid Glass, animation feel on screen, real sign-in, real Ask replies, and capture permissions need an interactive check.
- Ask needs the Codex CLI (0.169.0 or newer) or Claude Code (2.1.0 or newer) installed and signed in. Before distributing Ask widely, confirm that OpenAI's and Anthropic's terms allow third-party apps to drive their subscription CLIs.

## 0.0.1 (build 6) · 2026-11-17

- First GitHub release. Refreshed all seven Settings pages with a compact graphite palette, native sidebar vibrancy, grouped material rows, aligned controls, and accessible opaque fallbacks. Existing preferences and shortcuts are preserved.
