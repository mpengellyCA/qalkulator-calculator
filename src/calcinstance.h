// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CalcInstance — the per-window state for one calculator "thread": its own
// result register (exposed to QML as `history` — `register` is a C++ keyword)
// and its own CalculatorEngine (its own live preview / ans). Secondary windows
// also carry a vivid accent colour; the primary uses an invalid colour, meaning
// "follow the OS accent". Owned by the WindowManager.

#pragma once

#include <QColor>
#include <QObject>

// Full definitions: moc needs the Q_PROPERTY pointer types complete to register
// their metatypes.
#include "calculatorengine.h"
#include "resultregistermodel.h"

class CalcInstance : public QObject
{
    Q_OBJECT

    Q_PROPERTY(ResultRegisterModel *history READ history CONSTANT)
    Q_PROPERTY(CalculatorEngine *engine READ engine CONSTANT)
    Q_PROPERTY(QColor accentColor READ accentColor NOTIFY accentColorChanged)
    Q_PROPERTY(bool hasAccent READ hasAccent NOTIFY accentColorChanged)
    Q_PROPERTY(int instanceId READ instanceId CONSTANT)
    Q_PROPERTY(bool primary READ primary CONSTANT)

public:
    explicit CalcInstance(int id, bool primary, QObject *parent = nullptr);

    ResultRegisterModel *history() const { return m_history; }
    CalculatorEngine *engine() const { return m_engine; }

    QColor accentColor() const { return m_accent; }
    bool hasAccent() const { return m_accent.isValid(); }
    void setAccentColor(const QColor &c);

    int instanceId() const { return m_id; }
    bool primary() const { return m_primary; }

Q_SIGNALS:
    void accentColorChanged();

private:
    ResultRegisterModel *m_history = nullptr;
    CalculatorEngine *m_engine = nullptr;
    QColor m_accent; // invalid => use the OS accent (primary window)
    int m_id;
    bool m_primary;
};
