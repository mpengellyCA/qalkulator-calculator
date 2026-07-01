#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build a portable AppImage of QalKulator (Qt6 · KF6/Kirigami · libqalculate).
#
# The hard parts of a Kirigami AppImage:
#   * the QQC2 "org.kde.desktop" style (qqc2-desktop-style) is selected by string
#     at runtime, so linuxdeploy-plugin-qt's static import scan never sees it — we
#     copy it in by hand and let a second linuxdeploy pass patch its rpaths.
#   * libqalculate loads unit/currency definitions from a data dir at runtime, so
#     we bundle /usr/share/qalculate and point XDG_DATA_DIRS at the AppDir.
#   * Kirigami needs an icon theme for its symbolic icons — Breeze is bundled.
#
# Usage: packaging/appimage/build-appimage.sh [VERSION]
# Runs from the repo root. Expects Qt6/KF6/libqalculate dev packages installed.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

VERSION="${1:-$("${repo_root}/version.sh")}"
ARCH="$(uname -m)"
export ARCH VERSION
export QMAKE="${QMAKE:-qmake6}"
APPDIR="${repo_root}/AppDir"

echo "==> Building QalKulator ${VERSION} for AppImage (${ARCH})"

# --- 1. Configure, build, install into a clean AppDir --------------------------
rm -rf build-appimage "${APPDIR}"
cmake -B build-appimage -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DQALKULATOR_VERSION="${VERSION}"
cmake --build build-appimage -j"$(nproc)"
DESTDIR="${APPDIR}" cmake --install build-appimage

# --- 2. Locate Qt6 / KF6 QML + plugin dirs (portable across distros) ----------
QML_DIR="$(${QMAKE} -query QT_INSTALL_QML 2>/dev/null || true)"
if [ -z "${QML_DIR}" ] || [ ! -d "${QML_DIR}" ]; then
    for c in /usr/lib/*/qt6/qml /usr/lib/qt6/qml /usr/lib64/qt6/qml; do
        [ -d "$c" ] && QML_DIR="$c" && break
    done
fi
echo "==> Qt QML dir: ${QML_DIR}"

# --- 3. Bundle libqalculate definition data (needed at runtime) ---------------
if [ -d /usr/share/qalculate ]; then
    echo "==> Bundling libqalculate data"
    mkdir -p "${APPDIR}/usr/share/qalculate"
    cp -a /usr/share/qalculate/. "${APPDIR}/usr/share/qalculate/"
fi

# --- 4. Bundle the Breeze icon theme (Kirigami symbolic icons) ----------------
if [ -d /usr/share/icons/breeze ]; then
    echo "==> Bundling Breeze icon theme"
    mkdir -p "${APPDIR}/usr/share/icons"
    cp -a /usr/share/icons/breeze "${APPDIR}/usr/share/icons/"
    [ -d /usr/share/icons/breeze-dark ] && cp -a /usr/share/icons/breeze-dark "${APPDIR}/usr/share/icons/"
fi

# --- 5. Fetch linuxdeploy + the Qt plugin -------------------------------------
tools="${repo_root}/.appimage-tools"
mkdir -p "${tools}"
fetch() { # url dest
    [ -f "$2" ] || wget -q -O "$2" "$1"
    chmod +x "$2"
}
fetch "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage" \
      "${tools}/linuxdeploy-${ARCH}.AppImage"
fetch "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-${ARCH}.AppImage" \
      "${tools}/linuxdeploy-plugin-qt-${ARCH}.AppImage"
LD="${tools}/linuxdeploy-${ARCH}.AppImage"
# Extract so it runs without FUSE (GitHub runners have none).
export PATH="${tools}:${PATH}"
export APPIMAGE_EXTRACT_AND_RUN=1

# --- 6. Runtime env hook (sourced by the generated AppRun) --------------------
# Force the KDE desktop style, and make bundled data/icons discoverable.
mkdir -p "${APPDIR}/apprun-hooks"
cat > "${APPDIR}/apprun-hooks/qalkulator-env.sh" <<'HOOK'
export QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-org.kde.desktop}"
export XDG_DATA_DIRS="${APPDIR}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-}"
HOOK

# --- 7. First pass: bundle the app + Qt (scans qml/ for imports) --------------
export QML_SOURCES_PATHS="${repo_root}/src/qml"
"${LD}" --appdir "${APPDIR}" --plugin qt \
    --desktop-file "${APPDIR}/usr/share/applications/io.github.mpengellyca.qalkulator.desktop" \
    --icon-file "${APPDIR}/usr/share/icons/hicolor/scalable/apps/io.github.mpengellyca.qalkulator.svg"

# --- 8. Hand-bundle the org.kde.desktop QQC2 style (string-loaded) ------------
# linuxdeploy-plugin-qt stages QML modules under AppDir/usr/qml.
dest_qml="${APPDIR}/usr/qml"
mkdir -p "${dest_qml}"
extra_libs=()
if [ -n "${QML_DIR}" ]; then
    for mod in org/kde/desktop org/kde/kirigami org/kde/kirigami/styles; do
        src="${QML_DIR}/${mod}"
        if [ -d "${src}" ] && [ ! -d "${dest_qml}/${mod}" ]; then
            echo "==> Bundling QML module ${mod}"
            mkdir -p "${dest_qml}/${mod}"
            cp -a "${src}/." "${dest_qml}/${mod}/"
        fi
    done
    # Collect the style's plugin .so files so their deps get bundled + rpatched.
    while IFS= read -r -d '' so; do
        extra_libs+=(--library "${so}")
    done < <(find "${dest_qml}/org/kde/desktop" -name '*.so' -print0 2>/dev/null)
fi

# --- 9. Second pass: patch the hand-bundled libs, then output the AppImage ----
export OUTPUT="QalKulator-${VERSION}-${ARCH}.AppImage"
"${LD}" --appdir "${APPDIR}" "${extra_libs[@]}" --output appimage

echo "==> Produced: ${OUTPUT}"
ls -lh "${OUTPUT}"
