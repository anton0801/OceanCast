#!/bin/bash
#
# Compiles the iOS app's real models and coders, then drives the live API with
# them. This is what proves the Swift ↔ PHP wire format actually matches instead
# of only looking like it does.
#
#   ./run.sh [base-url]      default: http://127.0.0.1:8791
#
# It creates one throwaway account and deletes it again. Never point it at
# production data.

set -euo pipefail

BASE="${1:-http://127.0.0.1:8791}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HERE/../../../SugarBloom"

if [ ! -d "$APP/Model" ]; then
    echo "Cannot find the app sources at $APP" >&2
    exit 1
fi

echo "Compiling the app's models against the contract test…"
xcrun swiftc -O -o "$HERE/contract" \
    "$HERE/main.swift" \
    "$APP/Model/Models.swift" \
    "$APP/Model/Units.swift" \
    "$APP/Model/Formatting.swift" \
    "$APP/Services/API/APIModels.swift"

"$HERE/contract" "$BASE"
