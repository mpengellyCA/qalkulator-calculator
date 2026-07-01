add_executable(qalkulator)

target_sources(qalkulator PRIVATE
    main.cpp
    calculatorengine.cpp
    calculatorengine.h
    resultregistermodel.cpp
    resultregistermodel.h
    currencyservice.cpp
    currencyservice.h
)

# Windows: embed the app icon (Explorer/taskbar/title-bar icon).
if(WIN32)
    target_sources(qalkulator PRIVATE ${CMAKE_SOURCE_DIR}/packaging/windows/qalkulator.rc)
endif()

# KConfigXT: generates QalkulatorConfig (singleton) from qalkulator.kcfg + qalkulatorconfig.kcfgc
kconfig_add_kcfg_files(qalkulator GENERATE_MOC qalkulatorconfig.kcfgc)

set(QALKULATOR_QML_FILES
    qml/Main.qml
    qml/ModeBar.qml
    qml/ExpressionField.qml
    qml/ResultPreview.qml
    qml/ResultRegisterView.qml
    qml/ResultRegisterPopup.qml
    qml/AmountHistoryPopup.qml
    qml/Keypad.qml
    qml/ConverterView.qml
    qml/StatusBar.qml
    qml/AccessKeyOverlay.qml
    qml/KeyCap.qml
    qml/SettingsDialog.qml
    qml/UnitPickerPopup.qml
)

# Shared QML singletons (app-wide style constants + the unit catalogue).
set_source_files_properties(qml/Style.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Units.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

ecm_add_qml_module(qalkulator URI io.github.mpengellyca.qalkulator GENERATE_PLUGIN_SOURCE)
ecm_target_qml_sources(qalkulator SOURCES ${QALKULATOR_QML_FILES})
ecm_target_qml_sources(qalkulator SOURCES qml/Style.qml qml/Units.qml)

target_include_directories(qalkulator PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

target_compile_definitions(qalkulator PRIVATE QALKULATOR_VERSION="${QALKULATOR_VERSION}")

target_link_libraries(qalkulator PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    KF6::Kirigami
    KF6::CoreAddons
    KF6::ConfigCore
    KF6::ConfigGui
    KF6::I18n
    KF6::I18nQml
    PkgConfig::QALCULATE
)

if(TARGET KF6::Crash)
    target_link_libraries(qalkulator PRIVATE KF6::Crash)
    target_compile_definitions(qalkulator PRIVATE HAVE_KCRASH)
endif()

ecm_finalize_qml_module(qalkulator)

install(TARGETS qalkulator ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
