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
 adds a FAN row with hwmon fan speeds (RPM) to the cpu box.
EOF

mkdir -p "$DIST"
dpkg-deb --build --root-owner-group "$STAGE" "$DIST/btop_${version}_${arch}.deb"
echo "$DIST/btop_${version}_${arch}.deb"
