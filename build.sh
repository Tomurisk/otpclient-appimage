#!/usr/bin/env bash
set -euo pipefail
alias wget='wget --https-only --secure-protocol=TLSv1_2'

###############################################
# Config
###############################################

# Detect Docker
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup; then
    SUDO=""
else
    SUDO="sudo"
fi

# Content blocks
source content_blocks.sh

# Architecture
: "${ARCH:=$(uname -m)}"

# Versions
VERSION="3.2.0"
AIT_VER="1.9.1"
LBENC_VER="1.0.15"
LCOTP_VER="3.0.0"

# Definitions
AIT_DIR="/tmp/appimagetool"
APPDIR="$(pwd)/AppDir"

# Hashes
TARBALL_SHA256="8c3102d3c34ff8ab74e52eaa1be585eb432b62930d51672e5a5df4c95a2e62b2"
LBENC_SHA256="1b797b1b403358949201049675f70a495dee8e338df52f7790c7ad6e6a0027fa"
LCOTP_SHA256="ff0b9ce208c4c6542a0f1e739cf31978fbf28848c573837c671a6cb7b56b2c12"
AMD64_AIT_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
ARM64_AIT_SHA256="f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158"

# Set the right arch variables
if [[ "$ARCH" == "x86_64" ]]; then
    AIT_SHA256="$AMD64_AIT_SHA256"
elif [[ "$ARCH" == "aarch64" ]]; then
    AIT_SHA256="$ARM64_AIT_SHA256"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Clear old resources
rm -rf "$APPDIR" "$AIT_DIR" OTPClient-* libbaseencode-* libcotp-*

###############################################
# Fetch appimagetool dynamically
###############################################

APPIMAGETOOL="$AIT_DIR/appimagetool.AppImage"
mkdir -p "$AIT_DIR"

if [ ! -f "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    wget -O "$APPIMAGETOOL" \
      "https://github.com/AppImage/appimagetool/releases/download/${AIT_VER}/appimagetool-${ARCH}.AppImage"

    if echo "$AIT_SHA256  $APPIMAGETOOL" | sha256sum -c -; then
        echo "appimagetool checksum OK"
        chmod +x "$APPIMAGETOOL"
    else
        echo "ERROR: Checksum mismatch!"
        exit 1
    fi
fi

###############################################
# Prepare sources
###############################################

mkdir -p "$APPDIR"

wget -O "OTPClient-${VERSION}.tar.gz" \
  "https://github.com/paolostivanin/OTPClient/archive/refs/tags/v${VERSION}.tar.gz"
wget -O "libbaseencode-${LBENC_VER}.tar.gz" \
  "https://github.com/paolostivanin/libbaseencode/archive/refs/tags/v${LBENC_VER}.tar.gz"
wget -O "libcotp-${LCOTP_VER}.tar.gz" \
  "https://github.com/paolostivanin/libcotp/archive/refs/tags/v${LCOTP_VER}.tar.gz"

check() {
    local file=$1
    local sum=$2

    if echo "$sum  $file" | sha256sum -c -; then
        echo "$file checksum OK — extracting"
        tar xf "$file"
    else
        echo "ERROR: $file checksum mismatch!"
        exit 1
    fi
}

check "OTPClient-${VERSION}.tar.gz" "$TARBALL_SHA256"
check "libbaseencode-${LBENC_VER}.tar.gz" "$LBENC_SHA256"
check "libcotp-${LCOTP_VER}.tar.gz" "$LCOTP_SHA256"

###############################################
# Build libraries
###############################################

DIRS=("libbaseencode-${LBENC_VER}" "libcotp-${LCOTP_VER}")

for i in "${!DIRS[@]}"; do
    dir="${DIRS[$i]}"

    echo "=== Building $dir ==="

    pushd "$dir" >/dev/null

    mkdir -p build
    pushd build >/dev/null

    cmake ..
    make -j$(nproc)
    $SUDO make install
    $SUDO ldconfig

    popd >/dev/null   # exit build/
    popd >/dev/null   # exit $dir/

    echo "=== Finished $dir ==="
done

###############################################
# Apply dynamic-prefix patch inline
###############################################

pushd "OTPClient-${VERSION}" >/dev/null

dyn_pref
patch -p1 < dynamic-prefix.patch

###############################################
# Create src/config.h.in required by the patch
###############################################

helper_func

# Build with AppDir as install prefix
mkdir -p build
pushd build >/dev/null

cmake -DCMAKE_INSTALL_PREFIX="$APPDIR/usr" ..
make -j$(nproc)
$SUDO make install

popd >/dev/null  # exit build/
popd >/dev/null  # exit OTPClient/

###############################################
# Static assets
###############################################

# Fix permissions
$SUDO chown -R "$(id -un):$(id -un)" "$APPDIR"

ICON="$APPDIR/usr/share/icons/hicolor/scalable/apps/com.github.paolostivanin.OTPClient.svg"
DESKTOP_FILE="$APPDIR/usr/share/applications/com.github.paolostivanin.OTPClient.desktop"

sed -i 's/Exec=.*/Exec=\/AppRun/' "$DESKTOP_FILE"
cp "$DESKTOP_FILE" "$APPDIR"

cp "$ICON" "$APPDIR"

rm -rf "$APPDIR/usr/share/metainfo"

###############################################
# Bundle runtime libraries and their licenses
###############################################

LIBS="/usr/lib64"
LICENSES="/usr/share/licenses"
mkdir -p "$APPDIR/$LIBS" "$APPDIR/$LICENSES"

for lib in \
    "$LIBS/libzbar.so.0."* \
    "$LIBS/libjpeg.so.62."* \
    "$LIBS/libprotobuf-c.so.1."* \
    "$LIBS/libqrencode.so.4."* \
    "$LIBS/libjansson.so.4."*
do
    for f in $lib; do
        if [ -f "$f" ]; then
            cp "$f" "$APPDIR/$LIBS"
            base=$(basename "$f")

            # Extract the SONAME part (libname.so.X)
            soname=$(echo "$base" | sed -E 's/(\.so\.[0-9]+).*/\1/')

            # Create symlink only if missing
            if [ ! -e "$APPDIR/$LIBS/$soname" ]; then
                ln -sf "$base" "$APPDIR/$LIBS/$soname"
            fi
        else
            echo "ERROR: Required library missing: $lib"
            exit 1
        fi
    done
done

LIBCOTP="/usr/local/lib64/libcotp.so.${LCOTP_VER}"
cp "$LIBCOTP" "$APPDIR/$LIBS"
base=$(basename "$LIBCOTP")
soname=$(echo "$base" | sed -E 's/(\.so\.[0-9]+).*/\1/')

if [ ! -e "$APPDIR/$LIBS/$soname" ]; then
    ln -sf "$base" "$APPDIR/$LIBS/$soname"
fi

# Licenses
cp -r "$LICENSES/zbar-libs"     "$APPDIR/$LICENSES"
cp -r "$LICENSES/libjpeg-turbo" "$APPDIR/$LICENSES"
cp -r "$LICENSES/protobuf"      "$APPDIR/$LICENSES"
cp -r "$LICENSES/qrencode-libs" "$APPDIR/$LICENSES"
cp -r "$LICENSES/jansson"       "$APPDIR/$LICENSES"

mkdir -p "$APPDIR/$LICENSES/libcotp"
cp -r "libcotp-${LCOTP_VER}/LICENSE" "$APPDIR/$LICENSES/libcotp"

mkdir -p "$APPDIR/$LICENSES/otpclient"
cp -r "OTPClient-${VERSION}/LICENSE" "$APPDIR/$LICENSES/otpclient"

###############################################
# Registration script
###############################################

cat > "$APPDIR/usr/bin/registration" << 'EOF'
#!/bin/bash
set -euo pipefail

ACTION="${1:-}"
APPDIR="${2:-}"

OTPCLIENT="com.github.paolostivanin.OTPClient"

ICON_SRC="$APPDIR/$OTPCLIENT.svg"
DESKTOP_SRC="$APPDIR/$OTPCLIENT.desktop"

ICON_TARGET1="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_TARGET2="$HOME/.icons/hicolor/scalable/apps"
DESKTOP_TARGET="$HOME/.local/share/applications"

register() {
    echo "Where to place the OTPClient icon?"
    echo "(1) ~/.local/share/icons"
    echo "(2) ~/.icons"
    echo "Any other key to cancel"
    read -r choice

    case "$choice" in
        1) ICON_DEST="$ICON_TARGET1" ;;
        2) ICON_DEST="$ICON_TARGET2" ;;
        *) echo "Canceled"; exit 0 ;;
    esac

    mkdir -p "$ICON_DEST"
    cp "$ICON_SRC" "$ICON_DEST"

    mkdir -p "$DESKTOP_TARGET"
    cp "$DESKTOP_SRC" "$DESKTOP_TARGET"

    # Fix Exec to point to the AppImage
    sed -i "s|^Exec=.*|Exec=$APPIMAGE|" "$DESKTOP_TARGET/$OTPCLIENT.desktop"

    echo "OTPClient registered"
}

unregister() {
    rm -f "$ICON_TARGET1/$OTPCLIENT.svg"
    rm -f "$ICON_TARGET2/$OTPCLIENT.svg"
    rm -f "$DESKTOP_TARGET/$OTPCLIENT.desktop"

    echo "OTPClient unregistered"
}

case "$ACTION" in
    --register) register ;;
    --unregister) unregister ;;
    *) echo "Unknown action"; exit 1 ;;
esac
EOF

chmod +x "$APPDIR/usr/bin/registration"

###############################################
# Simple AppRun
###############################################

cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"

case "${1:-}" in
    --reg|-r) exec "$HERE/usr/bin/registration" --register "$HERE" ;;
    --unreg|-u) exec "$HERE/usr/bin/registration" --unregister "$HERE" ;;
esac

export LD_LIBRARY_PATH="$HERE/usr/lib64:${LD_LIBRARY_PATH:-}"
export OTPCLIENT_PREFIX="$HERE/usr"
exec "$HERE/usr/bin/otpclient" "$@"
EOF

chmod +x "$APPDIR/AppRun"

###############################################
# Build AppImage
###############################################

RUNTIME="runtime-${ARCH}"

appimage_key

wget -O "$AIT_DIR/$RUNTIME.sig" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/$RUNTIME.sig"
wget -O "$AIT_DIR/$RUNTIME" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/$RUNTIME"

if gpg --verify "$AIT_DIR/$RUNTIME.sig" "$AIT_DIR/$RUNTIME" 2>/dev/null; then
    echo "Runtime signature OK"
    ARCH=${ARCH} "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream --runtime-file "$AIT_DIR/$RUNTIME" "$APPDIR"
else
    echo "ERROR: Signature verification failed!"
    exit 1
fi

###############################################
# Cleanup
###############################################

shopt -s extglob
rm -rf "$APPDIR" OTPClient-!(*.AppImage) libbaseencode-* libcotp-*

echo "Done"
