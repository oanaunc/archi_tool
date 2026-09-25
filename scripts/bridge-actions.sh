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
    toolchain)     sw_vers; xcodebuild -version; swift --version ;;
    open-app)      open "$ROOT/build/Oanarina Archi Tool.app" ;;
    quit-app)      osascript -e 'quit app "Oanarina Archi Tool"' ;;
    screenshot-app) "$ROOT/scripts/screenshot-app.sh" ;;
    ui-check)      "$ROOT/scripts/ui-check.sh" ;;
    *) echo "Unknown action: $1"; return 64 ;;
  esac
}
