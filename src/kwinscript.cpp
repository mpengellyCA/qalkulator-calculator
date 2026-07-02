// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "kwinscript.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QStandardPaths>

namespace
{
const QString kPluginId = QStringLiteral("qalkulator-magnetic");
const QString kScriptRel =
    QStringLiteral("kwin/scripts/qalkulator-magnetic/contents/code/main.js");

// A KDE Plasma session? (The script only means anything under KWin.)
bool isKdeSession()
{
    const QString cur = qEnvironmentVariable("XDG_CURRENT_DESKTOP");
    return cur.split(QLatin1Char(':')).contains(QLatin1String("KDE"), Qt::CaseInsensitive);
}

QDBusMessage kwinCall(const QString &path, const QString &iface, const QString &method)
{
    return QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), path, iface, method);
}
} // namespace

KWinScript::KWinScript(QObject *parent)
    : QObject(parent)
{
    // Supported only on a KDE session where the script is actually installed.
    m_scriptPath = QStandardPaths::locate(QStandardPaths::GenericDataLocation, kScriptRel);
    m_supported = isKdeSession() && !m_scriptPath.isEmpty();
}

bool KWinScript::enabled() const
{
    KSharedConfig::Ptr cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    return cfg->group(QStringLiteral("Plugins")).readEntry(kPluginId + QStringLiteral("Enabled"), false);
}

void KWinScript::setEnabled(bool on)
{
    if (!m_supported || on == enabled()) {
        return;
    }

    // Persist the flag so KWin also loads/unloads it on the next login.
    KSharedConfig::Ptr cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    cfg->group(QStringLiteral("Plugins")).writeEntry(kPluginId + QStringLiteral("Enabled"), on);
    cfg->sync();

    // Apply live over DBus so the toggle takes effect now (no re-login needed).
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (on) {
        QDBusMessage load = kwinCall(QStringLiteral("/Scripting"),
                                     QStringLiteral("org.kde.kwin.Scripting"),
                                     QStringLiteral("loadScript"));
        load << m_scriptPath << kPluginId;
        bus.call(load);
        bus.call(kwinCall(QStringLiteral("/Scripting"),
                          QStringLiteral("org.kde.kwin.Scripting"),
                          QStringLiteral("start")));
    } else {
        QDBusMessage unload = kwinCall(QStringLiteral("/Scripting"),
                                       QStringLiteral("org.kde.kwin.Scripting"),
                                       QStringLiteral("unloadScript"));
        unload << kPluginId;
        bus.call(unload);
    }

    Q_EMIT enabledChanged();
}
