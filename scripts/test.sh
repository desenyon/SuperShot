#!/bin/zsh
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"
swift_path=$(xcrun --find swiftc)
plugin_path="${swift_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_flags=(--disable-xctest --build-system swiftbuild)
if [[ -f "$plugin_path" ]]; then
    test_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin_path")
fi
swift test "${test_flags[@]}" "$@"
