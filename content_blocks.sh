appimage_key() {
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
}

# GPL‑3.0 licensed code
dyn_pref() {
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
}

# GPL‑3.0 licensed code
helper_func() {
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

# GPL‑3.0 licensed code
cat << 'EOF' > src/data-path.h
#pragma once
#include <glib.h>

gchar *get_data_file_path(const gchar *partial_path);

EOF
}
