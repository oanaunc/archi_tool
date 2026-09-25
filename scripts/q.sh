#!/bin/bash
# Queue a bridge action and wait for it (used from the dev VM). Usage: scripts/q.sh action [timeout_s]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; id="$(date +%s%N)-$1"; t="${2:-170}"
echo "$1" > "$ROOT/.bridge/queue/$id.job"
for ((i=0;i<t;i++)); do [[ -f "$ROOT/.bridge/logs/$id.done" ]] && break; sleep 1; done
if [[ -f "$ROOT/.bridge/logs/$id.done" ]]; then tail -c 6000 "$ROOT/.bridge/logs/$id.log"; echo "[exit $(cat "$ROOT/.bridge/logs/$id.done")]"; else echo "[still running: $id]"; fi
