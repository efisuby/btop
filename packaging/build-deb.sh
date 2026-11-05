#!/bin/bash
# Build a local Ubuntu .deb of this btop checkout.
# Usage: packaging/build-deb.sh   -> dist/btop_<version>_<arch>.deb
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
BUILD=$ROOT/build-deb
STAGE=$BUILD/stage
DIST=$ROOT/dist

: "${CXX:=g++-14}" "${CC:=gcc-14}"
export CXX CC

base_version=$(grep -oP 'project\(\s*btop\s+VERSION\s+\K[0-9.]+' CMakeLists.txt || true)
[[ -n "$base_version" ]] || base_version=$(git describe --tags --abbrev=0 | sed 's/^v//')
version="${base_version}+git$(git log -1 --format=%cd --date=format:%Y%m%d).$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
arch=$(dpkg --print-architecture)

rm -rf "$BUILD"
cmake -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBTOP_GPU=ON
cmake --build "$BUILD" -j"$(nproc)"
DESTDIR="$STAGE" cmake --install "$BUILD"

# Runtime dependencies from the linked shared libraries
mkdir -p "$BUILD/shlib/debian"
echo "Source: btop" > "$BUILD/shlib/debian/control"
depends=$(cd "$BUILD/shlib" && dpkg-shlibdeps -O -e"$STAGE/usr/bin/btop" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')

installed_size=$(du -sk "$STAGE/usr" | cut -f1)
mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: btop
Version: $version
Architecture: $arch
Maintainer: efisuby <efisuby@users.noreply.github.com>
Installed-Size: $installed_size
Depends: $depends
Section: utils
Priority: optional
Homepage: https://github.com/efisuby/btop
Description: Modern and colorful command line resource monitor (fork with fan speeds)
 btop++ resource monitor built from the efisuby/btop fork:
 adds fan speeds and PWM, P/E core clusters, PSI, NVMe temperatures,
 GPU throttle reasons and per-process VRAM / systemd unit columns.
EOF

# RAPL energy_uj (CPU watts) and other processes' /proc files are root-only:
# grant the same capabilities as upstream `make setcap` on install.
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v setcap >/dev/null 2>&1; then
	setcap "cap_perfmon,cap_dac_read_search=+ep" /usr/bin/btop || echo "btop: setcap failed, CPU watts will be unavailable" >&2
fi
POSTINST
chmod 0755 "$STAGE/DEBIAN/postinst"

mkdir -p "$DIST"
dpkg-deb --build --root-owner-group "$STAGE" "$DIST/btop_${version}_${arch}.deb"
echo "$DIST/btop_${version}_${arch}.deb"
