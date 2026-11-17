#!/bin/zsh
# Renders the app's main surfaces to PNG files, offscreen, in dark and light appearance.
# Shows no windows and never activates the app, so it is safe to run while the Mac is in use.
# System glass cannot render offscreen: floating surfaces appear with their opaque fallback.
# Usage: scripts/preview.sh [output-dir]   (PREVIEW_ONLY=editor limits scenes by name)
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"
output="${1:-docs/previews}"
swift build >/dev/null
mkdir -p .build/preview "$output"
swift scripts/make-editor-fixture.swift .build/preview/fixture.png
"$(swift build --show-bin-path)/SuperShot" --render-previews "$output" .build/preview/fixture.png
print "Rendered previews to $output"
