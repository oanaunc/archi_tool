# Brief for development agents

- The repository is on the user's Mac, reachable ONLY through the `mcp__remote-devices__device_bash` tool at `$HOME/mnt/archi_tool` (not the cloud `Bash` tool, which cannot see it). Reference projects: `$HOME/mnt/archi_tool/other_projects/` (read-only; GPL — you may adapt algorithms; keep attribution in a header comment).
- Read `AGENTS.md`, `docs/ARCHITECTURE.md` and the existing sources in `app/Sources/ArchiCore` before writing code.
- Write files with heredocs (`cat > path <<'EOF' ... EOF`) or small python edits. Each device_bash call has a ~170 s limit.
- Compile on the Mac: `cd $HOME/mnt/archi_tool && scripts/q.sh build 175` (tests: `scripts/q.sh test 175`). It prints only `file:line: error:` lines, then `BUILD OK` or `BUILD FAILED`. If it prints `[still running: …]`, wait and read `.bridge/logs/<id>.log`/`.done` later. Other agents build concurrently: fix only errors in YOUR files; if another agent's file breaks the build, wait ~60 s and retry (do not edit their files). Never run `push`, `package`, or git commands — the lead commits.
- Swift language mode 5, macOS 14 SDK APIs only. `ArchiCore` uses Foundation only. The core document type is `ArchiDocument` (never `Document`). `Editor` is `@MainActor`.
- Header for new files: `// Oanarina Archi Tool — GPL-3.0-or-later`.
- Quality bar: real working implementations, not placeholders. Handle edge cases (degenerate geometry, empty docs). Add XCTest cases for algorithms in `app/Tests/ArchiCoreTests/<YourArea>Tests.swift`.
- Finish with your files compiling. Final report (≤ 250 words): what you implemented, public API added, known gaps.
