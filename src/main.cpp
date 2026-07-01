// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// QalKulator — a modern, keyboard-first calculator for KDE Plasma.
// Bootstrap: creates the single libqalculate CALCULATOR, wires the thin C++
// services, registers them as QML singletons, and loads the QML UI.

#include <QApplication>
#include <QFile>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QResource>
#include <QTimer>

#ifdef Q_OS_WIN
// Declared directly rather than via <windows.h>, whose macros (OPTIONAL, IN, …)
// collide with libqalculate's enums included further down.
extern "C" __declspec(dllimport) void __stdcall OutputDebugStringW(const wchar_t *);
#endif

#include <KAboutData>
#include <KLocalizedContext>
#include <KLocalizedString>
#include <KLocalizedQmlContext>

#ifdef HAVE_KCRASH
#include <KCrash>
#endif

#include <libqalculate/qalculate.h>

#include "calculatorengine.h"
#include "currencyservice.h"
#include "qalkulatorconfig.h"
#include "resultregistermodel.h"

#ifndef QALKULATOR_VERSION
#define QALKULATOR_VERSION "0.1.0-dev"
#endif

namespace
{
QtMessageHandler g_previousMessageHandler = nullptr;

// Silence one benign, upstream warning: the org.kde.desktop QQC2 style binds the
// StandardKey shortcut (Copy/Paste — which map to multiple key bindings) in a
// TextField's right-click context menu with a singular `sequence:`, so Qt logs
// "Only binding to one of multiple key bindings". It's not our code and harmless;
// everything else is passed through untouched.
void messageFilter(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (message.contains(QLatin1String("Only binding to one of multiple key bindings"))) {
        return;
    }
    if (g_previousMessageHandler) {
        g_previousMessageHandler(type, context, message);
    } else {
        // qInstallMessageHandler() returns nullptr when it replaced Qt's built-in
        // default, so forwarding only "if previous" would swallow ALL output —
        // which on Windows hid QML load failures entirely (the app just exited
        // -1 with no message). Emit the formatted line ourselves.
        const QString formatted = qFormatLogMessage(type, context, message);
#ifdef Q_OS_WIN
        // A GUI-subsystem app has no console, so stderr is usually unconnected;
        // the debugger channel is where Qt's own default handler writes (visible
        // in DebugView, or Wine's +debugstr).
        const QString line = formatted + QLatin1Char('\n');
        OutputDebugStringW(reinterpret_cast<const wchar_t *>(line.utf16()));
#endif
        fprintf(stderr, "%s\n", qUtf8Printable(formatted));
        fflush(stderr);
    }
}
} // namespace

int main(int argc, char *argv[])
{
    g_previousMessageHandler = qInstallMessageHandler(messageFilter);

    QApplication app(argc, argv);

#ifdef Q_OS_WIN
    // Windows has no system icon theme, so QQC2 `icon.name` (swap, history, clear,
    // refresh…) resolve to nothing and the buttons render blank. MSYS2 ships Breeze
    // as a compiled Qt resource (BINARY_ICONS_RESOURCE=ON, no loose SVGs) which the
    // deploy bundles next to the exe — register it and make Breeze the theme so the
    // icons resolve from :/icons/breeze.
    {
        // breeze-icons.rcc roots its content at ":/" (index.theme, actions/16/…),
        // but a Qt icon theme must live at <searchpath>/<name>/. Remap it under
        // "/icons/breeze" via registerResource()'s mapRoot so the theme resolves
        // at :/icons/breeze.
        const QString rcc = QCoreApplication::applicationDirPath()
                            + QStringLiteral("/breeze-icons.rcc");
        if (QFile::exists(rcc)
            && QResource::registerResource(rcc, QStringLiteral("/icons/breeze"))) {
            QIcon::setThemeSearchPaths(QIcon::themeSearchPaths()
                                       << QStringLiteral(":/icons"));
            QIcon::setThemeName(QStringLiteral("breeze"));
        }
        QIcon::setFallbackThemeName(QStringLiteral("breeze"));
    }
#endif

    // Kirigami looks best (and picks up Breeze) with the desktop style.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    KLocalizedString::setApplicationDomain(QByteArrayLiteral("qalkulator"));

    KAboutData aboutData(
        QStringLiteral("qalkulator"),
        i18nc("@title", "QalKulator"),
        QStringLiteral(QALKULATOR_VERSION),
        i18n("A fast, keyboard-first calculator for the desktop."),
        KAboutLicense::Custom,
        i18n("© 2026 Mike Pengelly"));
    aboutData.addLicenseText(i18n("GNU Affero General Public License v3.0 or later"));
    aboutData.addAuthor(i18nc("@info:credit", "Mike Pengelly"),
                        i18nc("@info:credit", "Author"),
                        QString(),
                        QStringLiteral("https://github.com/mpengellyCA"));
    aboutData.setHomepage(QStringLiteral("https://github.com/mpengellyCA/qalkulator-calculator"));
    aboutData.setDesktopFileName(QStringLiteral("io.github.mpengellyca.qalkulator"));
    aboutData.setBugAddress(QByteArrayLiteral("https://github.com/mpengellyCA/qalkulator-calculator/issues"));
    KAboutData::setApplicationData(aboutData);

    // On Linux the icon comes from the theme; on Windows fromTheme() is empty, so
    // leave the window icon unset there and let the exe's embedded .ico (see
    // packaging/windows/qalkulator.rc) drive the title-bar/taskbar icon.
    const QIcon themeIcon = QIcon::fromTheme(QStringLiteral("io.github.mpengellyca.qalkulator"));
    if (!themeIcon.isNull()) {
        app.setWindowIcon(themeIcon);
    }
    app.setApplicationName(QStringLiteral("qalkulator"));
    app.setDesktopFileName(QStringLiteral("io.github.mpengellyca.qalkulator"));

#ifdef HAVE_KCRASH
    KCrash::initialize();
#endif

    // --- The one and only libqalculate engine (global CALCULATOR macro) ---
    new Calculator();
    CALCULATOR->loadExchangeRates();
    CALCULATOR->loadGlobalDefinitions();
    CALCULATOR->loadLocalDefinitions();

    // Optional engine smoke check (opt-in via QK_ENGINE_SPIKE) — off by default
    // so it never adds synchronous evaluation to normal startup.
    if (!qEnvironmentVariableIsEmpty("QK_ENGINE_SPIKE")) {
        qInfo() << "QalKulator engine spike:"
                << "2+2 =" << QString::fromStdString(CALCULATOR->calculateAndPrint("2+2", 2000))
                << "| 200 + 15% =" << QString::fromStdString(CALCULATOR->calculateAndPrint("200 + 15%", 2000))
                << "| 100 USD to EUR =" << QString::fromStdString(CALCULATOR->calculateAndPrint("100 USD to EUR", 2000));
    }

    // --- Thin C++ services ---
    auto *registerModel = new ResultRegisterModel(&app);
    auto *engine = new CalculatorEngine(registerModel, &app);
    auto *currency = new CurrencyService(engine, &app);

    registerModel->restore();      // rehydrate the tape from KConfig
    currency->refreshIfStale();    // async; never blocks

    // --- QML ---
    QQmlApplicationEngine qmlEngine;
    KLocalization::setupLocalizedContext(&qmlEngine);

    qmlRegisterSingletonInstance("io.github.mpengellyca.qalkulator", 1, 0, "Engine", engine);
    qmlRegisterSingletonInstance("io.github.mpengellyca.qalkulator", 1, 0, "Register", registerModel);
    qmlRegisterSingletonInstance("io.github.mpengellyca.qalkulator", 1, 0, "Currency", currency);
    qmlRegisterSingletonInstance("io.github.mpengellyca.qalkulator", 1, 0, "Config", QalkulatorConfig::self());

    // These instances are C++-owned (parented to the app / KConfigXT); make that
    // explicit so the QML engine never garbage-collects them.
    for (QObject *o : {static_cast<QObject *>(engine), static_cast<QObject *>(registerModel), static_cast<QObject *>(currency), static_cast<QObject *>(QalkulatorConfig::self())}) {
        QQmlEngine::setObjectOwnership(o, QQmlEngine::CppOwnership);
    }

    // Result-format / precision / angle-unit changes must refresh the live result
    // immediately (the Settings dialog only writes Config).
    const QList<void (QalkulatorConfig::*)()> formatSignals = {
        &QalkulatorConfig::resultFormatChanged,
        &QalkulatorConfig::decimalPlacesChanged,
        &QalkulatorConfig::thousandsSeparatorChanged,
        &QalkulatorConfig::angleUnitChanged,
    };
    for (auto sig : formatSignals) {
        QObject::connect(QalkulatorConfig::self(), sig, engine, &CalculatorEngine::refreshFormatting);
    }

    QObject::connect(&app, &QApplication::aboutToQuit, registerModel, &ResultRegisterModel::persist);
    QObject::connect(&app, &QApplication::aboutToQuit, []() { QalkulatorConfig::self()->save(); });

    qmlEngine.loadFromModule("io.github.mpengellyca.qalkulator", "Main");
    if (qmlEngine.rootObjects().isEmpty()) {
        return -1;
    }

    // Dev-only headless screenshot hook: QK_SCREENSHOT=/path.png [QK_SCREENSHOT_SIZE=WxH]
    // renders the window (software backend + offscreen) and quits. No effect on
    // normal runs.
    const QByteArray shotPath = qgetenv("QK_SCREENSHOT");
    if (!shotPath.isEmpty()) {
        if (auto *win = qobject_cast<QQuickWindow *>(qmlEngine.rootObjects().constFirst())) {
            int w = 440, h = 780;
            const QList<QByteArray> sz = qgetenv("QK_SCREENSHOT_SIZE").split('x');
            if (sz.size() == 2) {
                w = sz.at(0).toInt();
                h = sz.at(1).toInt();
            }
            win->resize(w, h);
            bool okMode = false;
            const int startMode = qEnvironmentVariableIntValue("QK_START_MODE", &okMode);
            if (okMode && startMode >= 0 && startMode <= 2) {
                win->setProperty("mode", startMode);
            }
            if (!qEnvironmentVariableIsEmpty("QK_DEMO")) {
                if (okMode && startMode >= 1) {
                    // Seed the active converter's amount so the shot shows a live result.
                    QVariant convVar;
                    QMetaObject::invokeMethod(win, "activeConverter", Q_RETURN_ARG(QVariant, convVar));
                    if (auto *conv = qvariant_cast<QObject *>(convVar)) {
                        const QString amount = (startMode == 2) ? QStringLiteral("100") : QStringLiteral("3");
                        QMetaObject::invokeMethod(conv, "loadAmount", Q_ARG(QVariant, QVariant(amount)));
                    }
                } else {
                    for (const QString &e : {QStringLiteral("1250 * 1.13"), QStringLiteral("200 + 15%"),
                                             QStringLiteral("12% of 340"), QStringLiteral("(3+4)^2"),
                                             QStringLiteral("sqrt(2)")}) {
                        engine->commit(e);
                    }
                }
            }
            QTimer::singleShot(1600, win, [win, shotPath]() {
                win->grabWindow().save(QString::fromLocal8Bit(shotPath));
                QCoreApplication::quit();
            });
        }
    }

    return app.exec();
}
