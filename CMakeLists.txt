cmake_minimum_required(VERSION 3.20)

# Full version X.Y.Z. X.Y come from the VERSION file; Z is a hex commit index
# injected by CI (-DQALKULATOR_VERSION=...). Fall back to "<X.Y>.0-dev" for local builds.
if(NOT QALKULATOR_VERSION)
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" QALKULATOR_BASE_VERSION LIMIT_COUNT 1)
    string(STRIP "${QALKULATOR_BASE_VERSION}" QALKULATOR_BASE_VERSION)
    set(QALKULATOR_VERSION "${QALKULATOR_BASE_VERSION}.0-dev")
endif()

project(qalkulator LANGUAGES CXX)

# Windows: compile the .rc that embeds the app icon into the exe.
if(WIN32)
    enable_language(RC)
endif()

set(QT_MIN_VERSION 6.6.0)
set(KF6_MIN_VERSION 6.0.0)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMInstallIcons)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    QuickControls2
    Network
)

find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Kirigami
    CoreAddons
    Config
    I18n
)

# libqalculate via pkg-config
find_package(PkgConfig REQUIRED)
pkg_check_modules(QALCULATE REQUIRED IMPORTED_TARGET libqalculate)

# Optional niceties
find_package(KF6Crash ${KF6_MIN_VERSION})
set_package_properties(KF6Crash PROPERTIES TYPE OPTIONAL
    PURPOSE "Graceful crash handling and reporting")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src)

install(PROGRAMS io.github.mpengellyca.qalkulator.desktop DESTINATION ${KDE_INSTALL_APPDIR})

# Generate the AppStream metainfo so its <release> tracks the real build version
# (what software centres display) instead of a hardcoded value.
string(TIMESTAMP QALKULATOR_RELEASE_DATE "%Y-%m-%d" UTC)
configure_file(io.github.mpengellyca.qalkulator.metainfo.xml.in
    ${CMAKE_CURRENT_BINARY_DIR}/io.github.mpengellyca.qalkulator.metainfo.xml @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/io.github.mpengellyca.qalkulator.metainfo.xml
    DESTINATION ${KDE_INSTALL_METAINFODIR})
install(FILES icons/io.github.mpengellyca.qalkulator.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# Companion KWin script for magnetic window linking — a KDE-exclusive feature
# (Wayland clients can't self-position; the compositor can). Ships on Linux only
# and is opt-in: users enable it in System Settings → Window Management → KWin
# Scripts (or via the in-app toggle). No effect on Windows/macOS.
if(NOT WIN32 AND NOT APPLE)
    install(DIRECTORY packaging/kwin/qalkulator-magnetic
        DESTINATION ${KDE_INSTALL_DATADIR}/kwin/scripts)
endif()

# --- Packaging (CPack: TGZ + DEB + RPM) ------------------------------------
set(CPACK_PACKAGE_NAME "qalkulator")
set(CPACK_PACKAGE_VERSION "${QALKULATOR_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "A fast, keyboard-first calculator with unit and currency conversion")
set(CPACK_PACKAGE_VENDOR "Mike Pengelly")
set(CPACK_PACKAGE_CONTACT "Mike Pengelly <https://github.com/mpengellyCA>")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/mpengellyCA/qalkulator-calculator")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_PACKAGING_INSTALL_PREFIX "/usr")
set(CPACK_PACKAGE_FILE_NAME "qalkulator-${QALKULATOR_VERSION}-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_STRIP_FILES ON)

# Debian/Ubuntu (.deb): auto-detect linked-library deps; name the QML runtime
# modules that are dlopened (not caught by shlibdeps) as best-effort extras.
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Mike Pengelly <https://github.com/mpengellyCA>")
set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_RECOMMENDS "qml6-module-org-kde-kirigami, qml6-module-qtquick-controls, qml6-module-qtquick-layouts")

# Fedora/RHEL (.rpm): let rpmbuild auto-require the linked libraries.
set(CPACK_RPM_PACKAGE_LICENSE "AGPL-3.0-or-later")
set(CPACK_RPM_PACKAGE_GROUP "Applications/Productivity")
set(CPACK_RPM_PACKAGE_URL "https://github.com/mpengellyCA/qalkulator-calculator")
set(CPACK_RPM_PACKAGE_AUTOREQPROV ON)
set(CPACK_RPM_PACKAGE_REQUIRES "kf6-kirigami, qt6-qtdeclarative")

include(CPack)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
