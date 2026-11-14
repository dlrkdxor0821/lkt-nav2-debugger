#!/usr/bin/env bash
# Build a .deb that installs lkt-nav2-debugger as a system app.
#   packaging/build-deb.sh [version]      -> dist/lkt-nav2-debugger_<ver>_all.deb
# Install with:  sudo dpkg -i dist/lkt-nav2-debugger_<ver>_all.deb
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PKG="lkt-nav2-debugger"
VER="${1:-0.1.0}"
STAGE="$(mktemp -d)"

mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/opt/$PKG" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/scalable/apps"

# payload
cp -r "$ROOT/frontend" "$ROOT/bin" "$ROOT/DESIGN.md" "$STAGE/opt/$PKG/"
[ -d "$ROOT/backend" ] && cp -r "$ROOT/backend" "$STAGE/opt/$PKG/" || true
chmod 755 "$STAGE/opt/$PKG/bin/$PKG"

# system launcher -> /opt payload
cat > "$STAGE/usr/bin/$PKG" <<EOF
#!/usr/bin/env bash
exec env LKT_ROOT=/opt/$PKG /opt/$PKG/bin/$PKG "\$@"
EOF
chmod 755 "$STAGE/usr/bin/$PKG"

install -m644 "$ROOT/share/icon.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/$PKG.svg"
install -m644 "$ROOT/share/$PKG.desktop" "$STAGE/usr/share/applications/$PKG.desktop"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VER
Section: utils
Priority: optional
Architecture: all
Depends: python3, xdg-utils
Maintainer: leekt <dlrkdxor0821@gmail.com>
Description: rviz/rqt setup & launch for ROS2 Nav2 tuning
 Setup/launcher tool that generates rviz/rqt configs and shell aliases,
 handles CycloneDDS + Wi-Fi connection, and runs native or per-distro docker.
EOF

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/${PKG}_${VER}_all.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT" >/dev/null
rm -rf "$STAGE"
echo "built: $OUT"
dpkg-deb --info "$OUT" | sed -n '1,12p'
