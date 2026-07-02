// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WindowManager — the registry of open calculator instances (one per window),
// kept in open order. QML singleton: the cross-window Results popover queries it
// to browse other windows' histories, and window creation asks it for a new
// instance (which it stamps with a vivid, well-spaced accent colour).

#pragma once

#include <QColor>
#include <QList>
#include <QObject>

// Full definition: moc needs the CalcInstance* invokable return/arg types
// complete to register their metatypes.
#include "calcinstance.h"

class WindowManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int count READ count NOTIFY instancesChanged)

public:
    explicit WindowManager(QObject *parent = nullptr);

    int count() const { return static_cast<int>(m_instances.size()); }

    // Open order: index 0 is the primary window.
    Q_INVOKABLE CalcInstance *instanceAt(int i) const;
    Q_INVOKABLE int orderOf(CalcInstance *inst) const; // 0-based, -1 if absent

    // Create a secondary instance (accent-coloured). Window creation lives in QML.
    Q_INVOKABLE CalcInstance *createInstance();
    // Create an MCP agent instance: like a secondary (accent-coloured) but flagged
    // read-only and stamped with the controlling agent's name. Window creation is
    // driven from C++ (McpServer -> QML) rather than a user action.
    CalcInstance *createAgentInstance(const QString &agentName);
    // Drop a secondary instance (no-op for the primary).
    Q_INVOKABLE void removeInstance(CalcInstance *inst);

    // The primary instance, created once at startup from main.cpp.
    CalcInstance *createPrimary();

Q_SIGNALS:
    void instancesChanged();

private:
    QColor accentForIndex(int index) const;

    QList<CalcInstance *> m_instances;
    int m_nextId = 0;
    double m_baseHue = 0.0; // per-run random base; hues step by the golden angle
};
