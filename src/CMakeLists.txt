add_executable(kalk)

target_sources(kalk PRIVATE
    main.cpp
    calculatorengine.cpp
    calculatorengine.h
    resultregistermodel.cpp
    resultregistermodel.h
    currencyservice.cpp
    currencyservice.h
)

# KConfigXT: generates KalkConfig (singleton) from kalk.kcfg + kalkconfig.kcfgc
kconfig_add_kcfg_files(kalk GENERATE_MOC kalkconfig.kcfgc)

set(KALK_QML_FILES
    ../qml/Main.qml
    ../qml/ModeBar.qml
    ../qml/ExpressionField.qml
    ../qml/ResultPreview.qml
    ../qml/ResultRegisterView.qml
    ../qml/ResultRegisterPopup.qml
    ../qml/Keypad.qml
    ../qml/ConverterView.qml
    ../qml/StatusBar.qml
    ../qml/AccessKeyOverlay.qml
    ../qml/KeyCap.qml
    ../qml/SettingsDialog.qml
    ../qml/UnitPickerPopup.qml
)

# Shared QML singletons (app-wide style constants + the unit catalogue).
set_source_files_properties(../qml/Style.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(../qml/Units.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

ecm_add_qml_module(kalk URI io.github.mpengellyca.kalk GENERATE_PLUGIN_SOURCE)
ecm_target_qml_sources(kalk SOURCES ${KALK_QML_FILES})
ecm_target_qml_sources(kalk SOURCES ../qml/Style.qml ../qml/Units.qml)

target_include_directories(kalk PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

target_compile_definitions(kalk PRIVATE KALK_VERSION="${KALK_VERSION}")

target_link_libraries(kalk PRIVATE
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
    target_link_libraries(kalk PRIVATE KF6::Crash)
    target_compile_definitions(kalk PRIVATE HAVE_KCRASH)
endif()

ecm_finalize_qml_module(kalk)

install(TARGETS kalk ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
