#!/bin/zsh
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
bin_path=$(swift build -c "$configuration" --show-bin-path)
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx26.0" -I "$bin_path" \
    scripts/benchmark.swift "$bin_path/Document.o" "$bin_path/Render.o" \
    "$bin_path/Recognition.o" "$bin_path/Export.o" -o .build/benchmark
.build/benchmark
