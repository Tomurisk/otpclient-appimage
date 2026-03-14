#!/usr/bin/env bash
set -euo pipefail
alias wget='wget --https-only --secure-protocol=TLSv1_2'

###############################################
# Install Ubuntu dependencies
###############################################

sudo apt update
sudo apt install -y \
  wget cmake \
  libgtk-3-dev libsecret-1-dev \
  libprotobuf-dev libprotobuf-c-dev \
  libgcrypt20-dev libcotp-dev \
  libjansson-dev \
  libqrencode-dev libzbar-dev

###############################################
# Fetch appimagetool
###############################################

APPIMAGETOOL="$HOME/Programs/appimagetool-x86_64.AppImage"

mkdir -p "$HOME/Programs"

if [ ! -f "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    wget -O "$APPIMAGETOOL" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

###############################################
# Prepare sources
###############################################

VERSION="3.2.0"
APPDIR="$(pwd)/AppDir"
rm -rf "$APPDIR" OTPClient-*
mkdir -p "$APPDIR"

wget -O "v${VERSION}.tar.gz" \
  "https://github.com/paolostivanin/OTPClient/archive/refs/tags/v${VERSION}.tar.gz"

tar xf "v${VERSION}.tar.gz"
cd "OTPClient-${VERSION}"

###############################################
# Apply dynamic-prefix patch inline
###############################################

cat > dynamic-prefix.patch << 'EOF'
diff --git a/CMakeLists.txt b/CMakeLists.txt
index 06a7213..a4afc09 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -2,6 +2,11 @@ cmake_minimum_required(VERSION 3.16)
 project(OTPClient VERSION "3.2.0" LANGUAGES "C")
 include(GNUInstallDirs)
 
+configure_file(
+    ${CMAKE_CURRENT_SOURCE_DIR}/src/config.h.in
+    ${CMAKE_CURRENT_BINARY_DIR}/config.h
+)
+
 configure_file("src/common/version.h.in" "version.h")
 
 set (GETTEXT_PACKAGE ${CMAKE_PROJECT_NAME})
diff --git a/src/get-builder.c b/src/get-builder.c
index b8f4595..a1c6c52 100644
--- a/src/get-builder.c
+++ b/src/get-builder.c
@@ -1,21 +1,29 @@
 #include <gtk/gtk.h>
+#include <glib.h>
+#include "config.h"     // contains INSTALL_PREFIX and INSTALL_DATADIR
 #include "version.h"
 
 GtkBuilder *
-get_builder_from_partial_path (const gchar *partial_path)
+get_builder_from_partial_path(const gchar *partial_path)
 {
+    /* Allow runtime override */
+    const gchar *env_prefix = g_getenv("OTPCLIENT_PREFIX");
+
     const gchar *prefix;
+
 #ifndef USE_FLATPAK_APP_FOLDER
-    // cmake trims the last '/', so we have to manually add it later on
-    prefix = INSTALL_PREFIX;
+    /* If env var is set, use it; otherwise use CMake-generated prefix */
+    prefix = env_prefix ? env_prefix : INSTALL_PREFIX;
 #else
     prefix = "/app";
 #endif
-    gchar *path = g_strconcat (prefix, "/", partial_path, NULL);
 
-    GtkBuilder *builder = gtk_builder_new_from_file (path);
+    /* Build: <prefix>/share/otpclient/<partial_path> */
+    gchar *path = g_build_filename(prefix, "share", "otpclient", partial_path, NULL);
 
-    g_free (path);
+    GtkBuilder *builder = gtk_builder_new_from_file(path);
 
+    g_free(path);
     return builder;
 }
+
diff --git a/src/get-builder.h b/src/get-builder.h
index b3c5525..8dc2f93 100644
--- a/src/get-builder.h
+++ b/src/get-builder.h
@@ -2,7 +2,7 @@
 
 G_BEGIN_DECLS
 
-#define UI_PARTIAL_PATH         "share/otpclient/otpclient.ui"
+#define UI_PARTIAL_PATH "otpclient.ui"
 
 GtkBuilder *get_builder_from_partial_path (const gchar *partial_path);
 
EOF

patch -p1 < dynamic-prefix.patch

###############################################
# Create src/config.h.in required by the patch
###############################################

cat << 'EOF' > src/config.h.in
#pragma once

#define INSTALL_PREFIX "@CMAKE_INSTALL_PREFIX@"
#define INSTALL_DATADIR "@CMAKE_INSTALL_FULL_DATADIR@"
EOF

# Build with AppDir as install prefix
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$APPDIR/usr" ..
make -j$(nproc)
make install

cd ..

###############################################
# Static assets
###############################################

ICON="$APPDIR/usr/share/icons/hicolor/scalable/apps/com.github.paolostivanin.OTPClient"
DESKTOP_FILE="$APPDIR/usr/share/applications/com.github.paolostivanin.OTPClient.desktop"

sed -i 's/Exec=.*/Exec=\/AppRun/' "$DESKTOP_FILE"
cp "$DESKTOP_FILE" "$APPDIR"

cp "$ICON"* "$APPDIR"

rm -rf "$APPDIR/usr/share/metainfo"

###############################################
# Bundle runtime libraries
###############################################

LIBS="/usr/lib/x86_64-linux-gnu"
mkdir -p "$APPDIR/$LIBS"

for lib in \
    "$LIBS/libzbar.so.0."* \
    "$LIBS/libcotp.so.3."* \
    "$LIBS/libjpeg.so.8."*
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

export LD_LIBRARY_PATH="$HERE/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export OTPCLIENT_PREFIX="$HERE/usr"
exec "$HERE/usr/bin/otpclient" "$@"
EOF

chmod +x "$APPDIR/AppRun"

###############################################
# Build AppImage
###############################################

cd ..
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR"

###############################################
# Cleanup
###############################################

shopt -s extglob
rm -rf "$APPDIR" OTPClient-!(*.AppImage) "v${VERSION}.tar.gz"

echo "Done"
