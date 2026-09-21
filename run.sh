#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
codesign --force -s - -i "com.qghs.Qstats" -r='designated => identifier "com.qghs.Qstats"' .build/release/Qstats 2>/dev/null || true
exec .build/release/Qstats
