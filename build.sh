#!/usr/bin/env bash
set -euo pipefail
alias wget='wget --https-only --secure-protocol=TLSv1_2'

###############################################
# Config
###############################################

# Content blocks
source content_blocks.sh

# Versions
VERSION="3.2.0"
AIT_VER="1.9.1"
LBENC_VER="1.0.15"
LCOTP_VER="3.0.0"

# Definitions
AIT_DIR="/tmp/appimagetool"
APPDIR="$(pwd)/AppDir"

# Checksum
TARBALL_SHA256="8c3102d3c34ff8ab74e52eaa1be585eb432b62930d51672e5a5df4c95a2e62b2"
AIT_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
LBENC_SHA256="1b797b1b403358949201049675f70a495dee8e338df52f7790c7ad6e6a0027fa"
LCOTP_SHA256="ff0b9ce208c4c6542a0f1e739cf31978fbf28848c573837c671a6cb7b56b2c12"

# Clear old resources
rm -rf "$APPDIR" "$AIT_DIR" OTPClient-* libbaseencode-* libcotp-*

###############################################
# Fetch appimagetool
###############################################

APPIMAGETOOL="$AIT_DIR/appimagetool-x86_64.AppImage"
mkdir -p "$AIT_DIR"

if [ ! -f "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    wget -O "$APPIMAGETOOL" \
      "https://github.com/AppImage/appimagetool/releases/download/${AIT_VER}/appimagetool-x86_64.AppImage"

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
    make
    make install
    ldconfig

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
make install

popd >/dev/null  # exit build/
popd >/dev/null  # exit OTPClient/

###############################################
# Static assets
###############################################

ICON="$APPDIR/usr/share/icons/hicolor/scalable/apps/com.github.paolostivanin.OTPClient.svg"
DESKTOP_FILE="$APPDIR/usr/share/applications/com.github.paolostivanin.OTPClient.desktop"

sed -i 's/Exec=.*/Exec=\/AppRun/' "$DESKTOP_FILE"
cp "$DESKTOP_FILE" "$APPDIR"

cp "$ICON" "$APPDIR"

rm -rf "$APPDIR/usr/share/metainfo"

###############################################
# Bundle runtime libraries
###############################################

LIBS="/usr/lib64"
mkdir -p "$APPDIR/$LIBS"

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

RUNTIME="runtime-x86_64"

appimage_key

wget -O "$AIT_DIR/runtime-x86_64.sig" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/$RUNTIME.sig"
wget -O "$AIT_DIR/runtime-x86_64" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/$RUNTIME"

if gpg --verify "$AIT_DIR/$RUNTIME.sig" "$AIT_DIR/$RUNTIME" 2>/dev/null; then
    echo "Runtime signature OK"
    ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream --runtime-file "$AIT_DIR/$RUNTIME" "$APPDIR"
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
