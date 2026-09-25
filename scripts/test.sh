#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app" && swift test 2>&1 | grep -v "^\[" | grep -E "error|warning: unre|failed|passed|Executed|XCTAssert|Test Suite 'All" | tail -80
