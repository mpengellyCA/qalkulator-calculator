cmake_minimum_required(VERSION 3.20)

project(kalk VERSION 0.1.0 LANGUAGES CXX)

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

install(PROGRAMS io.github.mpengellyca.kalk.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES io.github.mpengellyca.kalk.metainfo.xml DESTINATION ${KDE_INSTALL_METAINFODIR})

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
