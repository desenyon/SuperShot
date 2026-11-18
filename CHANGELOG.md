# Changelog

All notable changes to SuperShot. Versions follow `CFBundleShortVersionString`; build numbers follow `CFBundleVersion`.

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
