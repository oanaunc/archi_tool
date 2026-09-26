# Whitelisted actions for scripts/mac-bridge.sh (re-read for every job).
run_action() {
  case "$1" in
    push)          cd "$ROOT" && git push -u origin main ;;
    website-push)  cd "$SITE" && git push origin HEAD ;;
    build)         "$ROOT/scripts/build.sh" ;;
    build-release) CONFIG=release "$ROOT/scripts/build.sh" ;;
    test)          "$ROOT/scripts/test.sh" ;;
    package)       "$ROOT/scripts/package.sh" ;;
    notary-profiles)
      for kc in $(security list-keychains | tr -d '"'); do security dump-keychain "$kc" 2>/dev/null; done | grep -i -o 'notary[^"]*' | sort -u
      grep -a -h -o 'keychain-profile[ =][^ ;]*' ~/.zsh_history ~/.bash_history 2>/dev/null | sort -u ;;
    notary-try)
      for n in notary notarytool NOTARY AC_PASSWORD AC_NOTARY oanarina Oanarina oanarina-notary photo-editor notarize notarization developer DeveloperID default archi; do
        if xcrun notarytool history --keychain-profile "$n" >/dev/null 2>&1; then echo "FOUND: $n"; fi
      done; echo done ;;
    icon)          cd "$ROOT" && swift scripts/make-icon.swift "$ROOT" && iconutil -c icns build/AppIcon.iconset -o app/Resources/AppIcon.icns && ls -la app/Resources ;;
    package-head)  # notarized DMG from the last commit, unaffected by work in progress
      cd "$ROOT" && rm -rf build/release-src && git worktree prune && git worktree add --detach build/release-src HEAD \
        && build/release-src/scripts/package.sh && mkdir -p dist && cp build/release-src/dist/*.dmg build/release-src/dist/SHA256SUMS.txt dist/ \
        && git worktree remove --force build/release-src ;;
    cli-template)  echo "" | "$ROOT/build/Oanarina Archi Tool.app/Contents/MacOS/archi-cli" --out "$ROOT/build/empty.archi"; ls -la "$ROOT/build/empty.archi" ;;
    demo-check)    "$ROOT/build/Oanarina Archi Tool.app/Contents/MacOS/archi-cli" "$ROOT/assets/demo/Cedar House.archi" --out "$ROOT/build/demo-plan.svg" </dev/null 2>&1 | tail -20; ls -la "$ROOT/build/demo-plan.svg" ;;
    open-demo)     open -a "$ROOT/build/Oanarina Archi Tool.app" "$ROOT/assets/demo/Cedar House.archi" ;;
    selftest)      "$ROOT/scripts/build.sh" >/dev/null && "$ROOT/build/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" --selftest 2>&1 | tail -80 ;;
    render-cedar)  # headless Cedar House renders → build/renders; build/render-args.txt may hold only
                   # "--render-size WxH" and "--render-supersample N" (anything else is ignored)
      "$ROOT/scripts/build.sh" >/dev/null || { echo "BUILD FAILED (build/build.log)"; return 1; }
      local rargs=() rtok=() t
      read -r -a rtok 2>/dev/null < "$ROOT/build/render-args.txt" || true
      for ((t=0; t+1<${#rtok[@]}; t++)); do
        case "${rtok[t]}" in
          --render-size)        [[ "${rtok[t+1]}" =~ ^[0-9]{2,5}x[0-9]{2,5}$ ]] && { rargs+=(--render-size "${rtok[t+1]}"); t=$((t+1)); } ;;
          --render-supersample) [[ "${rtok[t+1]}" =~ ^[1-4]$ ]] && { rargs+=(--render-supersample "${rtok[t+1]}"); t=$((t+1)); } ;;
        esac
      done
      cd "$ROOT" && "$ROOT/build/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" --render-cedar "$ROOT/build/renders" "${rargs[@]+"${rargs[@]}"}" 2>&1 | grep -v -e '^20[0-9][0-9]-' | tail -40; ls -la "$ROOT/build/renders" ;;
    toolchain)     sw_vers; xcodebuild -version; swift --version ;;
    open-app)      open "$ROOT/build/Oanarina Archi Tool.app" ;;
    quit-app)      osascript -e 'quit app "Oanarina Archi Tool"' ;;
    screenshot-app) "$ROOT/scripts/screenshot-app.sh" ;;
    ui-check)      "$ROOT/scripts/ui-check.sh" ;;
    tutorials)     # tutorial videos (scripts/make-tutorials.sh). build/tutorials/.request may hold a mode
                   # (record|check|status|stop) followed by tutorial names such as "01-getting-started" or "12"
      local req=() targs=() n
      read -r -a req 2>/dev/null < "$ROOT/build/tutorials/.request" || true
      [[ ${#req[@]} -gt 0 ]] || req=(record)
      case "${req[0]}" in record|check|status|stop) targs=("${req[0]}") ;; *) echo "Unknown tutorials mode: ${req[0]} (record|check|status|stop)"; return 64 ;; esac
      for n in "${req[@]:1}"; do
        [[ "$n" == dev || "$n" =~ ^[0-9]{2}(-[a-z0-9-]+)?$ ]] && targs+=("$n") || echo "ignored: $n"
      done
      "$ROOT/scripts/make-tutorials.sh" "${targs[@]}" ;;
    *) echo "Unknown action: $1"; return 64 ;;
  esac
}
