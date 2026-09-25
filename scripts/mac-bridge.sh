#!/bin/bash
# Oanarina Archi Tool — Mac bridge.
# Runs ONLY the fixed actions below when a job file appears in .bridge/queue.
# Start:  cd ~/Desktop/archi_tool && ./scripts/mac-bridge.sh     Stop: Ctrl+C
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$(cd "$ROOT/../oanarina_website" 2>/dev/null && pwd || true)"
Q="$ROOT/.bridge/queue"; L="$ROOT/.bridge/logs"
mkdir -p "$Q" "$L"
echo "Archi Tool bridge watching $Q (Ctrl+C to stop)"
run_action() {
  case "$1" in
    push)          cd "$ROOT" && git push -u origin main ;;
    website-push)  cd "$SITE" && git push origin HEAD ;;
    build)         "$ROOT/scripts/build.sh" ;;
    test)          "$ROOT/scripts/test.sh" ;;
    package)       "$ROOT/scripts/package.sh" ;;
    notary-profiles) security dump-keychain 2>/dev/null | grep -o 'com.apple.gke.notary.tool.saved-creds.[^"]*' | sed 's/.*saved-creds\.//' | sort -u ;;
    toolchain)     sw_vers; xcodebuild -version; swift --version; security find-identity -v -p codesigning | sed 's/"\(.*\)"/\1/' ;;
    open-app)      open "$ROOT/build/Oanarina Archi Tool.app" ;;
    screenshot-app) "$ROOT/scripts/screenshot-app.sh" ;;
    *) echo "Unknown action: $1"; return 64 ;;
  esac
}
while true; do
  for job in "$Q"/*.job; do
    [[ -e "$job" ]] || continue
    id="$(basename "$job" .job)"; action="$(head -n1 "$job" | tr -d '[:space:]')"
    rm -f "$job"
    echo "$(date '+%H:%M:%S') ▶ $id: $action"
    ( run_action "$action" ) > "$L/$id.log" 2>&1; status=$?
    echo "$status" > "$L/$id.done"
    echo "$(date '+%H:%M:%S') ■ $id: $action exit $status"
  done
  sleep 2
done
