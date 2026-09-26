#!/bin/bash
# Oanarina Archi Tool — GPL-3.0-or-later
# Generates the tutorial videos (tutorials/*.tut → build/tutorials/*.mp4) with the app's built-in recorder.
#
#   scripts/make-tutorials.sh record [names…]   records all (or the named) tutorials in the background; progress in
#                                               build/tutorials/record.log, "RECORDING DONE" when finished
#   scripts/make-tutorials.sh check [names…]    dry run: plays every step against the real editor without capturing video
#                                               and reports failed commands and the estimated duration of each tutorial
#   scripts/make-tutorials.sh probe [file|cedar] runs build/tutorials/probe.scr through archi-cli (optionally on a drawing;
#                                               cedar = the Cedar House sample)
#   scripts/make-tutorials.sh status            prints the end of the recorder log and the videos made so far
#   scripts/make-tutorials.sh stop              stops a running recording
#
# The app bundle is copied to build/tutorials/app first, so rebuilding the app does not disturb a running recording.
# The recorder opens its own window (a second instance of the app); leave that window alone while it records.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Oanarina Archi Tool.app"
OUT="$ROOT/build/tutorials"
mode="${1:-record}"; shift || true
mkdir -p "$OUT"
SRC="$ROOT/tutorials"
names=()
for n in "$@"; do
  if [[ "$n" == dev ]]; then SRC="$OUT/dev"; continue; fi   # scratch scripts in build/tutorials/dev
  if [[ "$n" == layer ]]; then names+=(--tutorial-capture layer); continue; fi
  names+=(--only "$n")
done

start_recorder() {  # $1 = log file, rest = extra arguments
  local log="$1"; shift
  [[ -x "$APP/Contents/MacOS/Oanarina Archi Tool" ]] || { echo "Build the app first (scripts/build.sh)."; exit 1; }
  if pgrep -f "$OUT/app/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" >/dev/null; then
    echo "A tutorial recording is already running (see $log)."; exit 1
  fi
  rm -rf "$OUT/app"; mkdir -p "$OUT/app"
  cp -R "$APP" "$OUT/app/"
  # The scripts in the source tree win over the bundled copy, so edited tutorials need no rebuild.
  : > "$log"
  # Started directly (not through `open`) so it shares this shell's folder permissions: an app launched on its own would
  # wait for a Desktop-folder permission prompt. -ApplePersistenceIgnoreState: no "reopen windows?" question after an
  # interrupted recording. Clicks reach the window without the app being active.
  nohup "$OUT/app/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" -ApplePersistenceIgnoreState YES \
        --record-tutorials "$OUT" --tutorials-source "$SRC" "$@" >> "$log" 2>&1 &
  echo "Recorder started; log: $log"
}

case "$mode" in
  record)
    start_recorder "$OUT/record.log" "${names[@]+"${names[@]}"}" ;;
  check)
    start_recorder "$OUT/check.log" --dry-run "${names[@]+"${names[@]}"}"
    for ((i=0;i<150;i++)); do grep -q "RECORDING DONE" "$OUT/check.log" 2>/dev/null && break; sleep 1; done
    cat "$OUT/check.log" ;;
  probe)
    CLI="$APP/Contents/MacOS/archi-cli"
    f="${1:-}"; [[ "$f" == cedar ]] && f="$ROOT/assets/demo/Cedar House.archi"
    if [[ -n "$f" ]]; then "$CLI" "$f" < "$OUT/probe.scr" > "$OUT/probe.out" 2>&1
    else "$CLI" < "$OUT/probe.scr" > "$OUT/probe.out" 2>&1; fi
    tail -c 3000 "$OUT/probe.out" ;;
  sample)   # stack of a recorder that seems stuck → build/tutorials/sample.txt
    pid=$(pgrep -f "$OUT/app/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" | head -1)
    [[ -n "$pid" ]] && sample "$pid" 2 -file "$OUT/sample.txt" >/dev/null 2>&1 && grep -A60 "Thread_[0-9]*   DispatchQueue_1\|com.apple.main-thread" "$OUT/sample.txt" | head -90 ;;
  crash)    # the newest crash report of the app, if the recorder died
    ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | head -6
    f=$(ls -t ~/Library/Logs/DiagnosticReports/Oanarina* 2>/dev/null | head -1)
    [[ -n "$f" ]] && { echo "$f"; grep -m1 -A3 '"exception"' "$f"; grep -o '"symbol":"[^"]*"' "$f" | head -40; } || echo "No crash report." ;;
  syslog)   # why a recorder ended (system log of the last 40 minutes)
    log show --last 40m --style compact --predicate 'eventMessage CONTAINS[c] "Oanarina Archi Tool" AND (eventMessage CONTAINS[c] "terminat" OR eventMessage CONTAINS[c] "kill" OR eventMessage CONTAINS[c] "exit" OR eventMessage CONTAINS[c] "crash" OR eventMessage CONTAINS[c] "jetsam")' 2>/dev/null | tail -25 ;;
  stop)
    pkill -f "$OUT/app/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" && echo "Recorder stopped." || echo "No recorder running." ;;
  status)
    pgrep -fl "Oanarina Archi Tool" || echo "No app instance running."
    for f in record check; do [[ -s "$OUT/$f.log" ]] && { echo "== $f.log"; tail -n 40 "$OUT/$f.log"; }; done
    ls -la "$OUT"/*.mp4 2>/dev/null ;;
  *) echo "Usage: $0 record|check|probe|status|stop [names…]"; exit 64 ;;
esac
