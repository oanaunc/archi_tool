#!/bin/bash
# Captures the frontmost Oanarina Archi Tool window to build/app-window.png
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WID=$(swift -e 'import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]; for w in l where (w["kCGWindowOwnerName"] as? String) == "Oanarina Archi Tool" && (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"]!); break }' 2>/dev/null)
echo "window: $WID"
screencapture -x -o -l "$WID" "$ROOT/build/app-window.png" && sips -g pixelWidth -g pixelHeight "$ROOT/build/app-window.png"
