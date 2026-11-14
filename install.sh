#!/usr/bin/env bash
# User-level install (no sudo): registers the app launcher + desktop entry + icon.
#   ./install.sh          install
#   ./install.sh --remove uninstall
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
NAME="lkt-nav2-debugger"

if [[ "${1:-}" == "--remove" ]]; then
  rm -f "$BIN/$NAME" "$APPS/$NAME.desktop" "$ICONS/$NAME.svg"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
  echo "[install] removed $NAME"
  exit 0
fi

mkdir -p "$BIN" "$APPS" "$ICONS"
chmod +x "$ROOT/bin/$NAME"
ln -sf "$ROOT/bin/$NAME" "$BIN/$NAME"
install -m644 "$ROOT/share/icon.svg" "$ICONS/$NAME.svg"
# Pin LKT_ROOT so the menu launch finds this checkout.
sed "s|^Exec=.*|Exec=env LKT_ROOT=$ROOT $NAME|" "$ROOT/share/$NAME.desktop" > "$APPS/$NAME.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true

echo "[install] installed $NAME (user-level)"
echo "  launch:  $NAME          (or app menu -> lkt-nav2-debugger)"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  note: add $BIN to PATH";; esac
