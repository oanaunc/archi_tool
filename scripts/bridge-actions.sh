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
    toolchain)     sw_vers; xcodebuild -version; swift --version ;;
    open-app)      open "$ROOT/build/Oanarina Archi Tool.app" ;;
    quit-app)      osascript -e 'quit app "Oanarina Archi Tool"' ;;
    screenshot-app) "$ROOT/scripts/screenshot-app.sh" ;;
    ui-check)      "$ROOT/scripts/ui-check.sh" ;;
    *) echo "Unknown action: $1"; return 64 ;;
  esac
}
