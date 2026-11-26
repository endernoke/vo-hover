#!/bin/zsh
# Builds VOHover.app, installs it to ~/Applications and (re)launches it.
# For installing from source and for development; releases use the DMG or Homebrew.
#   ./install.sh           install and open Settings
#   ./install.sh --quiet   install and start in the background
set -euo pipefail
cd "${0:A:h}"

case "${1:-}" in
  "" | --quiet) ;;
  *) echo "Usage: $0 [--quiet]" >&2; exit 2 ;;
esac

APP="$HOME/Applications/VOHover.app"
if [[ -d /Applications/VOHover.app ]]; then
  echo "Note: /Applications/VOHover.app (for example from Homebrew) is also installed." >&2
  echo "      Remove one copy so macOS doesn't mix up their permissions and login item." >&2
fi

./build.sh

# Stop any running copy before replacing it (SIGTERM; wait up to 5 seconds).
pkill -x VOHover 2>/dev/null || true
for _ in {1..50}; do pgrep -qx VOHover || break; sleep 0.1; done
pgrep -qx VOHover && { echo "VOHover didn't quit; quit it and run again." >&2; exit 1; }

mkdir -p "${APP:h}"
rm -rf "$APP"
ditto build/VOHover.app "$APP"

if [[ "${1:-}" == "--quiet" ]]; then
  open -g "$APP" --args --background
else
  open "$APP"
fi
echo "Installed $APP."
