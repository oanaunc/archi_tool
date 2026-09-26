# Tutorial videos

This folder holds the scripts of the Oanarina Archi Tool tutorial series. The app plays each script against its own
interface — typing into the command line, pressing ribbon and panel buttons, clicking on the plan, orbiting the 3D
view — and records the window as an MP4 with an animated cursor, click ripples, captions and keystroke pills. The
series builds the Cedar House (the bundled sample, `assets/demo/Cedar House.archi`) from an empty drawing.

| Script | Topic |
| --- | --- |
| `01-getting-started.tut` | Start screen, interface tour, opening the Cedar House, 2D/3D/Split/Sheet |
| `02-command-line.tut` | Typing commands, aliases, absolute/relative/polar coordinates, options, Enter to repeat, undo |
| `03-drawing-basics.tut` | Rectangles, circles, polylines, object snaps, ortho, fillet, trim, offset |
| `04-levels-and-walls.tut` | Levels, walls with thickness/height/justification, wall types, joins |
| `05-doors-and-windows.tut` | Windows and doors in walls, types, sizes, flipping, empty openings |
| `06-floors-roofs-stairs.tut` | Slabs, flat and shed roofs with overhangs, the canopy, a stair between levels |
| `07-rooms-and-annotation.tut` | Rooms with areas, dimensions, text, tags, hatches, room schedule |
| `08-3d-and-materials.tut` | The 3D view, orbiting, visual styles, materials, section box |
| `09-rendering.tut` | Saved cameras, the sun, the render window, rendering to a PNG |
| `10-sheets-and-pdf.tut` | Sheets, viewports at scale, title block, PLOT and PUBLISH to PDF |
| `11-import-export.tut` | DXF, IFC, OBJ, GLB and CSV export, IFC import |
| `12-scripting-and-ai.tut` | JavaScript console and the `archi` API, the agent server, `archi-cli --mcp` for Claude |

`setup/*.scr` are the Cedar House stages as plain command lines (walls, openings, floors and roofs). Tutorials 05–07
start from them with `runfile`, so each video begins where the previous one ended.

## Making the videos

On the Mac, with the app built (`scripts/build.sh`):

```
scripts/make-tutorials.sh check            # dry run: every step against the real editor, no video; lists problems and durations
scripts/make-tutorials.sh record           # all tutorials → build/tutorials/NN-name.mp4 (plus NN-name.log)
scripts/make-tutorials.sh record 01 02     # only some
scripts/make-tutorials.sh status           # progress;  scripts/make-tutorials.sh stop  stops a recording
```

From the development VM the same runs through the bridge: write the arguments to `build/tutorials/.request`
(for example `record 01 02`) and run `scripts/q.sh tutorials`.

The script starts a second instance of the app (`--record-tutorials DIR`), which opens its own window at 1440 × 900,
records every selected script and quits. Leave that window alone while it records (and do not quit it): the cursor in
the video is drawn by the recorder, but real mouse and keyboard input would still reach the window. The window is
captured with the app's own drawing (`cacheDisplay` plus SceneKit snapshots), so it records even while the screen is
locked and needs no screen-recording permission. The recorder switches the ribbon tab and the UI language setting while
it runs and restores them when it finishes. Videos are H.264 MP4 at 30 fps, at the
display's resolution (2880 × 1800 on a Retina display, 1440 × 900 otherwise). Recording takes about as long as the
video, longer for the 3D and rendering tutorials. In the app, **Tools ▸ Tutorial Videos** (`TUTORIALRECORD`) lists,
checks or records the bundled scripts in a new window.

Each video has a title card, the steps, and an end card. The `.log` file next to a video lists what was typed and what
the app answered; `PROBLEM` lines mark failed commands or UI targets that could not be found.

Launch options: `--record-tutorials DIR` (output folder), `--tutorials-source DIR` (scripts, default: the copy bundled
in the app), `--only NAME` (repeatable; a number or a name prefix), `--dry-run`, `--tutorial-scale 1|2` and
`--tutorial-log FILE`.

Commands in the scripts write their exports to `$TMP`, which is `/tmp/ArchiTutorial`.

## Script format

A script is UTF-8 text. `#` starts a comment line. The header (before `---`) has `title:` and `summary:` (shown on the
title card). Each following line is one step; words with spaces go in double quotes (`\"` for a quote).

| Step | Meaning |
| --- | --- |
| `open start` · `open new` · `open imperial` · `open building` | Start screen over an empty drawing, or a new drawing from a template |
| `open sample "Cedar House"` · `open file PATH` | Opens a bundled sample or a file |
| `runfile setup/NAME.scr` | Runs the command lines of a file silently (setup; not shown as typing) |
| `run COMMAND LINE` | Runs one command line silently |
| `caption "Title" "Subtitle"` · `caption off` | Lower-third caption, until the next one |
| `note "Text" [at x,y \| at TARGET] [top] [for SECONDS]` | A callout pointing at a model point or a UI element, or at the top |
| `type COMMAND ARGS…` | Types the command and each input with realistic keystrokes, pressing Enter after each word (as Space does in the app); `;` alone is an extra Enter; quoted words are typed as one input (text prompts) |
| `typeline LINE` | Types the whole line, then Enter |
| `enter` · `escape` | Enter (repeats the last command when idle) · Esc |
| `click TARGET` · `hover TARGET` | Moves the cursor to a UI element and clicks it (or only hovers) |
| `pick x,y` · `move x,y` | Clicks (or moves) on the plan at model coordinates; snaps apply as for a real click |
| `drag x1,y1 x2,y2` | Window (left to right) or crossing (right to left) selection on the plan |
| `camera NAME` · `style NAME` | Types `CAMERA NAME` or `VSCURRENT NAME` |
| `orbit DEGREES [SECONDS]` | Orbits the 3D view around its target (switches to 3D if needed) |
| `zoom extents` · `zoom in` · `zoom out` · `zoom FACTOR` · `zoom window x1,y1 x2,y2` | Animated plan zoom |
| `wait SECONDS` | Holds the picture |
| `speed CHARS_PER_SECOND` | Typing speed (default 14) |
| `js CODE` · `js clear` | Types a line into the JavaScript console (opens it) · clears the console |
| `close "Window title"` · `close sheet` | Closes another window (render, settings) · the open dialog sheet |
| `panels on` · `panels off` | Shows or hides the side panels |

Targets: `ribbon COMMAND` (the ribbon button that runs the command; its tab is opened first), `tab NAME` (ribbon tab),
`mode 2D|3D|Split|Sheet`, `panel NAME` (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History…),
`status NAME` (GRID, SNAP, ORTHO, POLAR, OTRACK, OSNAP, DYN, LWT), `start "Label"` or `button "Label" [in "Window"]`
(any button by its label, found by reading the window's text), and `commandline`.

How targets are found: ribbon tabs, the 2D/3D/Split/Sheet badge and the panel tabs by the order of the window's
controls; labelled buttons by reading the rendered window with Vision text recognition (in process, no permission
needed). Clicks are real mouse events, sent through the window (or straight to the view under the cursor when the
recorder's window is not the key window, for example while the Mac is locked). If a click has no effect, the recorder
performs the button's action directly — the same command or view change — and notes it in the report.

Leading `open`, `run`, `runfile` and `speed` steps run under the title card. Timing: 30 frames per second, typing at
about 14 characters per second with small random variation, short pauses after each Enter; long commands (renders,
exports) do not stretch the video. Keep each tutorial between 45 and 120 seconds — `check` reports the length.
