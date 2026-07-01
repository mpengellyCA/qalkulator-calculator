#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build, deploy and package QalKulator for Windows using MSYS2 (UCRT64).
# All dependencies (Qt6, KF6/Kirigami, libqalculate) are prebuilt MSYS2 packages,
# so this mirrors the Linux jobs: cmake build → install into a stage dir →
# gather every runtime DLL/QML module → zip (+ NSIS installer).
#
# Run inside an MSYS2 UCRT64 shell from the repo root.
# Usage: packaging/windows/deploy-windows.sh [VERSION]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

VERSION="${1:-$(./version.sh)}"
PREFIX="/ucrt64"
STAGE="${repo_root}/pkg-windows/QalKulator"
QT_QML="${PREFIX}/share/qt6/qml"

echo "==> Building QalKulator ${VERSION} for Windows (MSYS2 UCRT64)"
rm -rf "${repo_root}/pkg-windows" build-windows
mkdir -p "${STAGE}"

# --- 1. Configure, build, install into the stage dir --------------------------
cmake -B build-windows -S . -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DQALKULATOR_VERSION="${VERSION}"
cmake --build build-windows
cmake --install build-windows --prefix "${STAGE}"

EXE="${STAGE}/bin/qalkulator.exe"
[ -f "${EXE}" ] || { echo "!! qalkulator.exe not found at ${EXE}"; exit 1; }

# --- 2. Qt/QML deployment (Qt DLLs, platform plugin, imported QML modules) ----
# windeployqt scans our QML for imports and copies matching modules next to the
# exe (QtQuick, org.kde.kirigami, …). It does NOT catch the org.kde.desktop
# style (loaded by string at runtime) — handled below.
# MSYS2 ships qmlimportscanner under share/qt6/bin, not bin/, so windeployqt's
# --qmldir scan can't launch it ("Process failed to start"). Put it where
# windeployqt looks, and add that dir to PATH as a backstop.
export PATH="${PREFIX}/share/qt6/bin:${PATH}"
if [ ! -e "${PREFIX}/bin/qmlimportscanner.exe" ]; then
    _qis="$(command -v qmlimportscanner 2>/dev/null || find "${PREFIX}" -name 'qmlimportscanner.exe' 2>/dev/null | head -1)"
    [ -n "${_qis}" ] && cp "${_qis}" "${PREFIX}/bin/qmlimportscanner.exe" && echo "==> qmlimportscanner -> ${PREFIX}/bin (from ${_qis})"
fi
windeployqt6 --release --no-translations --qmldir "${repo_root}/src/qml" "${EXE}"

# --- 3. Hand-bundle the runtime-loaded org.kde.desktop QQC2 style + Kirigami --
for mod in org/kde/desktop org/kde/kirigami; do
    if [ -d "${QT_QML}/${mod}" ] && [ ! -d "${STAGE}/bin/${mod}" ]; then
        echo "==> Bundling QML module ${mod}"
        mkdir -p "${STAGE}/bin/$(dirname "${mod}")"
        cp -r "${QT_QML}/${mod}" "${STAGE}/bin/${mod}"
    fi
done

# --- 4. Close the DLL dependency graph (KF6, libqalculate + transitive) -------
# windeployqt only handles Qt libraries; KF6 and libqalculate DLLs (and the DLLs
# pulled in by the bundled QML plugins) must be resolved by hand. Iterate ldd
# over every PE file in the stage until no new MSYS2 DLL is copied.
echo "==> Resolving DLL dependencies"
for pass in $(seq 1 20); do
    copied=0
    while IFS= read -r dep; do
        [ -z "${dep}" ] && continue
        base="$(basename "${dep}")"
        if [ ! -f "${STAGE}/bin/${base}" ]; then
            cp "${dep}" "${STAGE}/bin/"
            copied=1
        fi
    done < <(
        find "${STAGE}" \( -iname '*.dll' -o -iname '*.exe' \) -print0 \
          | xargs -0 -r -n1 ldd 2>/dev/null \
          | awk '{print $3}' \
          | grep -iE "^${PREFIX}/bin/.*\.dll$" \
          | sort -u
    )
    echo "   pass ${pass}: copied=${copied}"
    [ "${copied}" -eq 0 ] && break
done

# --- 5. libqalculate definition data (units/currencies loaded at runtime) -----
if [ -d "${PREFIX}/share/qalculate" ]; then
    echo "==> Bundling libqalculate data"
    mkdir -p "${STAGE}/share"
    cp -r "${PREFIX}/share/qalculate" "${STAGE}/share/qalculate"
fi

# --- 6. Breeze icon theme (Kirigami symbolic icons) --------------------------
if [ -d "${PREFIX}/share/icons/breeze" ]; then
    echo "==> Bundling Breeze icon theme"
    mkdir -p "${STAGE}/share/icons"
    cp -r "${PREFIX}/share/icons/breeze" "${STAGE}/share/icons/breeze"
    [ -d "${PREFIX}/share/icons/breeze-dark" ] && cp -r "${PREFIX}/share/icons/breeze-dark" "${STAGE}/share/icons/breeze-dark"
fi

# --- 7. Portable ZIP ---------------------------------------------------------
ZIP="${repo_root}/QalKulator-${VERSION}-windows-x86_64.zip"
echo "==> Packaging portable zip"
( cd "${repo_root}/pkg-windows" && bsdtar -a -cf "${ZIP}" QalKulator )
echo "==> Produced: ${ZIP}"

# --- 8. NSIS installer (best-effort — never fails the build) ------------------
if command -v makensis >/dev/null 2>&1; then
    echo "==> Building NSIS installer"
    # mingw makensis needs native Windows paths, not MSYS /d/a/... paths.
    if makensis \
        -DVERSION="${VERSION}" \
        -DSTAGE="$(cygpath -w "${STAGE}")" \
        -DOUTDIR="$(cygpath -w "${repo_root}")" \
        "$(cygpath -w "${repo_root}/packaging/windows/qalkulator.nsi")"; then
        echo "==> Produced installer"
    else
        echo "!! NSIS installer failed (non-fatal); portable zip still produced"
    fi
else
    echo "!! makensis not found; skipping installer"
fi

ls -lh "${repo_root}"/QalKulator-*.zip "${repo_root}"/QalKulator-*-Setup.exe 2>/dev/null || true
