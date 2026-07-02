// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// KWinScript — the app-side control for the companion "magnetic window linking"
// KWin script (a KDE-exclusive feature). Reports whether the current session can
// use it (KDE + the script is installed), reads/writes the enabled flag in
// kwinrc, and loads/unloads it live over KWin's DBus so the toggle takes effect
// immediately. A no-op / unsupported everywhere else — the app never depends on it.

#pragma once

#include <QObject>
#include <QString>

class KWinScript : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool supported READ supported CONSTANT)
    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)

public:
    explicit KWinScript(QObject *parent = nullptr);

    bool supported() const { return m_supported; }
    bool enabled() const;

    Q_INVOKABLE void setEnabled(bool on);

Q_SIGNALS:
    void enabledChanged();

private:
    bool m_supported = false;
    QString m_scriptPath; // installed main.js (for live load), empty if not found
};
