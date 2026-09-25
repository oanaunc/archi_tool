#!/bin/bash
# Oanarina Archi Tool — Mac bridge.
# Runs ONLY the whitelisted actions in scripts/bridge-actions.sh when a job file appears in .bridge/queue.
# Start:  cd ~/Desktop/archi_tool && ./scripts/mac-bridge.sh     Stop: Ctrl+C
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$(cd "$ROOT/../oanarina_website" 2>/dev/null && pwd || true)"
Q="$ROOT/.bridge/queue"; L="$ROOT/.bridge/logs"
mkdir -p "$Q" "$L"
echo "Archi Tool bridge watching $Q (Ctrl+C to stop)"
while true; do
  for job in "$Q"/*.job; do
    [[ -e "$job" ]] || continue
    id="$(basename "$job" .job)"; action="$(head -n1 "$job" | tr -d '[:space:]')"
    rm -f "$job"
    echo "$(date '+%H:%M:%S') ▶ $action"
    ( source "$ROOT/scripts/bridge-actions.sh"; run_action "$action" ) > "$L/$id.log" 2>&1; status=$?
    echo "$status" > "$L/$id.done"
    echo "$(date '+%H:%M:%S') ■ $action exit $status"
  done
  sleep 2
done
