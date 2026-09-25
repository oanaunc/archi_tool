#!/bin/bash
# Runs the ArchiCore test suite. Full output: build/test-full.log.
# Prints every failure first, then the summary lines (so failures are never cut off).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
LOG="$ROOT/build/test-full.log"
cd "$ROOT/app" && swift test > "$LOG" 2>&1; rc=$?
grep -E "error:|XCTAssert|fatal|crash" "$LOG" | grep -v "^\[" | head -120
grep -E "Test Suite '.*' (passed|failed)|Executed" "$LOG" | tail -12
exit $rc
