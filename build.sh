#!/usr/bin/env bash
set -euo pipefail
alias wget='wget --https-only --secure-protocol=TLSv1_2'

###############################################
# Config
###############################################

VERSION="3.2.0"
APPDIR="$(pwd)/AppDir"
AIT_DIR="/tmp/appimagetool"
AIT_VER="1.9.1"

TARBALL_MD5="01a1e1c9b3d95a996d6f732faf9e8b0a"
AIT_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

# Clear old resources
rm -rf "$APPDIR" "$AIT_DIR" OTPClient-* "v${VERSION}.tar.gz"

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

wget -O "v${VERSION}.tar.gz" \
  "https://github.com/paolostivanin/OTPClient/archive/refs/tags/v${VERSION}.tar.gz"

if echo "$TARBALL_MD5  v${VERSION}.tar.gz" | md5sum -c -; then
    echo "Checksum OK – extracting tarball"
    tar xf "v${VERSION}.tar.gz"
    cd "OTPClient-${VERSION}"
else
    echo "ERROR: Checksum mismatch!"
    exit 1
fi

###############################################
# Apply dynamic-prefix patch inline
###############################################

cat > dynamic-prefix.patch << 'EOF'
diff --git a/CMakeLists.txt b/CMakeLists.txt
index 06a7213..7f14ceb 100644
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
@@ -132,7 +137,8 @@ set(GUI_SOURCE_FILES
         src/about_diag_cb.c
         src/show-qr-cb.c
         src/setup-signals-shortcuts.c
-        src/change-pwd-cb.c src/dbinfo-cb.c)
+        src/change-pwd-cb.c src/dbinfo-cb.c
+        src/data-path.c)
 
 set(CLI_HEADER_FILES
         src/cli/help.h
@@ -160,7 +166,8 @@ set(CLI_SOURCE_FILES
         src/common/aegis.c
         src/common/freeotp.c
         src/secret-schema.c
-        src/google-migration.pb-c.c)
+        src/google-migration.pb-c.c
+        src/data-path.c)
 
 if(BUILD_GUI AND BUILD_CLI)
         list(APPEND CLI_SOURCE_FILES
diff --git a/src/about_diag_cb.c b/src/about_diag_cb.c
index 9a67999..a1cc8ae 100644
--- a/src/about_diag_cb.c
+++ b/src/about_diag_cb.c
@@ -2,6 +2,7 @@
 #include <glib/gi18n.h>
 #include "version.h"
 #include "data.h"
+#include "data-path.h"
 
 void
 about_diag_cb (GSimpleAction *simple    __attribute__((unused)),
@@ -12,8 +13,11 @@ about_diag_cb (GSimpleAction *simple    __attribute__((unused)),
 
     const gchar *authors[] = {"Paolo Stivanin <info@paolostivanin.com>", NULL};
     const gchar *artists[] = {"Tobias Bernard (bertob) <https://tobiasbernard.com>", NULL};
-    const gchar *partial_path = "share/icons/hicolor/scalable/apps/com.github.paolostivanin.OTPClient.svg";
-    gchar *icon_abs_path = g_strconcat (INSTALL_PREFIX, "/", partial_path, NULL);
+
+    // Use dynamic prefix logic for the icon
+    gchar *icon_abs_path = get_data_file_path(
+        "icons/hicolor/scalable/apps/com.github.paolostivanin.OTPClient.svg"
+    );
 
     GtkWidget *ab_diag = gtk_about_dialog_new ();
     gtk_window_set_transient_for (GTK_WINDOW(app_data->main_window), GTK_WINDOW(ab_diag));
@@ -21,15 +25,18 @@ about_diag_cb (GSimpleAction *simple    __attribute__((unused)),
     gtk_about_dialog_set_program_name (GTK_ABOUT_DIALOG(ab_diag), PROJECT_NAME);
     gtk_about_dialog_set_version (GTK_ABOUT_DIALOG(ab_diag), PROJECT_VER);
     gtk_about_dialog_set_copyright (GTK_ABOUT_DIALOG(ab_diag), "2017-2022");
-    gtk_about_dialog_set_comments (GTK_ABOUT_DIALOG(ab_diag), _("Highly secure and easy to use GTK+ software for two-factor authentication that supports both Time-based One-time Passwords (TOTP) and HMAC-Based One-Time Passwords (HOTP)."));
+    gtk_about_dialog_set_comments (GTK_ABOUT_DIALOG(ab_diag),
+        _("Highly secure and easy to use GTK+ software for two-factor authentication that supports both Time-based One-time Passwords (TOTP) and HMAC-Based One-Time Passwords (HOTP)."));
     gtk_about_dialog_set_license_type (GTK_ABOUT_DIALOG(ab_diag), GTK_LICENSE_GPL_3_0);
     gtk_about_dialog_set_website (GTK_ABOUT_DIALOG(ab_diag), "https://github.com/paolostivanin/OTPClient");
     gtk_about_dialog_set_authors (GTK_ABOUT_DIALOG(ab_diag), authors);
     gtk_about_dialog_set_artists (GTK_ABOUT_DIALOG(ab_diag), artists);
+
     GdkPixbuf *logo = gdk_pixbuf_new_from_file (icon_abs_path, NULL);
     gtk_about_dialog_set_logo (GTK_ABOUT_DIALOG(ab_diag), logo);
+
     g_free (icon_abs_path);
-    g_signal_connect (ab_diag, "response", G_CALLBACK (gtk_widget_destroy), NULL);
 
+    g_signal_connect (ab_diag, "response", G_CALLBACK (gtk_widget_destroy), NULL);
     gtk_widget_show_all (ab_diag);
 }
diff --git a/src/get-builder.c b/src/get-builder.c
index b8f4595..3d5656a 100644
--- a/src/get-builder.c
+++ b/src/get-builder.c
@@ -1,21 +1,14 @@
 #include <gtk/gtk.h>
 #include "version.h"
+#include "data-path.h"
 
 GtkBuilder *
-get_builder_from_partial_path (const gchar *partial_path)
+get_builder_from_partial_path(const gchar *partial_path)
 {
-    const gchar *prefix;
-#ifndef USE_FLATPAK_APP_FOLDER
-    // cmake trims the last '/', so we have to manually add it later on
-    prefix = INSTALL_PREFIX;
-#else
-    prefix = "/app";
-#endif
-    gchar *path = g_strconcat (prefix, "/", partial_path, NULL);
+    gchar *path = get_data_file_path(partial_path);
 
-    GtkBuilder *builder = gtk_builder_new_from_file (path);
-
-    g_free (path);
+    GtkBuilder *builder = gtk_builder_new_from_file(path);
+    g_free(path);
 
     return builder;
 }
diff --git a/src/get-builder.h b/src/get-builder.h
index b3c5525..82b84ad 100644
--- a/src/get-builder.h
+++ b/src/get-builder.h
@@ -2,7 +2,7 @@
 
 G_BEGIN_DECLS
 
-#define UI_PARTIAL_PATH         "share/otpclient/otpclient.ui"
+#define UI_PARTIAL_PATH "otpclient/otpclient.ui"
 
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

cat << 'EOF' > src/data-path.c
#include <glib.h>
#include "config.h"

gchar *get_data_file_path(const gchar *partial_path)
{
    const gchar *env_prefix = g_getenv("OTPCLIENT_PREFIX");

#ifndef USE_FLATPAK_APP_FOLDER
    const gchar *prefix = env_prefix ? env_prefix : INSTALL_PREFIX;
#else
    const gchar *prefix = "/app";
#endif

    return g_build_filename(prefix, "share", partial_path, NULL);
}

EOF

cat << 'EOF' > src/data-path.h
#pragma once
#include <glib.h>

gchar *get_data_file_path(const gchar *partial_path);

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
    "$LIBS/libjpeg.so.8."* \
    "$LIBS/libprotobuf-c.so.1."* \
    "$LIBS/libqrencode.so.4."*
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
RUNTIME="runtime-x86_64"

gpg --import <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZjaeexYJKwYBBAHaRw8BAQdAhvHdHoBweX0uVRgfcnlzexrSg+TAbK2mU1TA
gi0TMC20NEFwcEltYWdlIHR5cGUgMiBydW50aW1lIDx0eXBlMi1ydW50aW1lQGFw
cGltYWdlLm9yZz6IlgQTFggAPgIbAwULCQgHAgYVCgkICwIEFgIDAQIeAQIXgBYh
BFcMd6zqQMDxt1iQLL+WzKVkkPaVBQJmN7FgBQkSzRXlAAoJEL+WzKVkkPaVCXsA
/0JxQPlr2AlKalt9LAGCXU633gBoXh8/sQQngGGWjhT2APoCls0XWL2qhx1jAIdr
AqDmOi3bdzBOpWBBIsOexhbdBrg4BGY2nnsSCisGAQQBl1UBBQEBB0CRVIEEu+Ft
W68O33iZCVDMIYUWdD59iXfQ7rHf8HxAEgMBCAeIfgQYFggAJhYhBFcMd6zqQMDx
t1iQLL+WzKVkkPaVBQJmNp57AhsMBQkDwmcAAAoJEL+WzKVkkPaVY7oA/icTs/E6
47LTon7ua021HdjQlwkHZOpa/hqBWQEB3w6GAQCbaPRxKcNN9Yfwxc6cIvfUORKz
+4OQzyesHV5P4fYLDw==
=r/5H
-----END PGP PUBLIC KEY BLOCK-----
EOF

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
rm -rf "$APPDIR" OTPClient-!(*.AppImage) "v${VERSION}.tar.gz"

echo "Done"
