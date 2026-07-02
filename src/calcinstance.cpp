// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "calcinstance.h"

#include "calculatorengine.h"
#include "resultregistermodel.h"

CalcInstance::CalcInstance(int id, bool primary, QObject *parent)
    : QObject(parent)
    , m_id(id)
    , m_primary(primary)
{
    // Each instance owns its own thread of results and its own engine (its own
    // live preview / ans). They serialize on the shared global calc mutex.
    m_history = new ResultRegisterModel(this);
    m_engine = new CalculatorEngine(m_history, this);
}

void CalcInstance::setAccentColor(const QColor &c)
{
    if (m_accent == c) {
        return;
    }
    m_accent = c;
    Q_EMIT accentColorChanged();
}

void CalcInstance::setAgent(const QString &name)
{
    m_agent = true;
    m_agentName = name;
}
