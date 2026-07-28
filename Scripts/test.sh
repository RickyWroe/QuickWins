#!/bin/bash
# Runs the test suite.
#
# The Swift Testing framework that ships with Command Line Tools is not on the default search
# path the way it is inside Xcode, so its framework and interop library locations are passed
# explicitly. With a full Xcode install, plain `swift test` also works.
set -euo pipefail

DEVELOPER_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
INTEROP_LIB="$(xcode-select -p)/Library/Developer/usr/lib"

if [ ! -d "$DEVELOPER_FRAMEWORKS/Testing.framework" ]; then
    echo "Swift Testing not found at $DEVELOPER_FRAMEWORKS" >&2
    echo "Install Xcode or the Command Line Tools, then re-run." >&2
    exit 1
fi

exec swift test \
    -Xswiftc -F -Xswiftc "$DEVELOPER_FRAMEWORKS" \
    -Xlinker -F -Xlinker "$DEVELOPER_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$DEVELOPER_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
    "$@"
