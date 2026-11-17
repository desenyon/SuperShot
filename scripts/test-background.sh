#!/bin/zsh
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"

# Keep desktop-dependent tests out of runs made while the user is working.
# This is an offscreen test run, not an isolated macOS desktop or VM.
# Detached overlay events and named pasteboards are safe: no global input is
# posted and NSPasteboard.general is never modified by these tests.
# New tests that show windows, capture the screen, send input, register global
# hotkeys, use the shared clipboard, or prompt for permissions must be excluded.
exec /usr/bin/nice -n 10 scripts/test.sh --jobs 2 \
    --skip closingRecorderWindowCancelsRecording "$@"
