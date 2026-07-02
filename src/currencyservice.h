// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CurrencyService — async exchange-rate refresh with graceful offline fallback.
//
// The blocking network fetch (CALCULATOR->fetchExchangeRates) runs on a worker
// thread and OUTSIDE the engine's calc mutex. Only the subsequent
// loadExchangeRates() (which mutates CALCULATOR state) is done under the shared
// mutex. Results are marshalled back to the GUI thread.

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class CalculatorEngine;
class QThread;

class CurrencyService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool refreshing READ refreshing NOTIFY refreshingChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString lastUpdated READ lastUpdated NOTIFY lastUpdatedChanged)
    Q_PROPERTY(QStringList currencies READ currencies NOTIFY currenciesChanged)
    // The configured default currency ("" = follow the system locale), and the
    // locale-derived currency code the empty setting resolves to (for the UI).
    Q_PROPERTY(QString defaultCurrency READ defaultCurrency WRITE setDefaultCurrency NOTIFY defaultCurrencyChanged)
    Q_PROPERTY(QString localeCurrency READ localeCurrency CONSTANT)

public:
    explicit CurrencyService(CalculatorEngine *engine, QObject *parent = nullptr);
    ~CurrencyService() override;

    bool refreshing() const { return m_refreshing; }
    bool available() const { return m_available; }
    QString lastUpdated() const { return m_lastUpdated; }
    QStringList currencies() const { return m_currencies; }

    QString defaultCurrency() const;
    QString localeCurrency() const { return m_localeCurrency; }
    // Persist the chosen default currency and apply it as libqalculate's local
    // currency (empty restores the locale default). Called from the settings UI.
    Q_INVOKABLE void setDefaultCurrency(const QString &code);

    Q_INVOKABLE void refresh();

    // Called once at startup (main.cpp): populate from cache immediately, and
    // kick off an async refresh if rates are stale and we can fetch. Never blocks.
    void refreshIfStale();

Q_SIGNALS:
    void refreshingChanged();
    void availableChanged();
    void lastUpdatedChanged();
    void currenciesChanged();
    void defaultCurrencyChanged();

private:
    void setRefreshing(bool v);
    void setAvailable(bool v);
    // Re-read cached state (currencies + lastUpdated + available) from CALCULATOR.
    void syncFromCache();
    // Applied on the GUI thread after a successful fetch.
    void onFetchFinished(bool ok);

    // Record the locale-derived local currency (once, at startup, before any
    // override) so the "System default" choice can be restored later.
    void captureLocaleCurrency();
    // Set libqalculate's local currency to `code`; empty falls back to the
    // captured locale default. Re-applied after each rate reload.
    void applyLocalCurrency(const QString &code);

    QStringList collectCurrencies() const;
    QString formatUpdated(long long secs) const;

    CalculatorEngine *m_engine = nullptr;
    QThread *m_fetchThread = nullptr; // in-flight network fetch, if any

    bool m_refreshing = false;
    bool m_available = false;
    QString m_lastUpdated;
    QStringList m_currencies;
    QString m_localeCurrency; // code the system locale resolves to (e.g. "CAD")
};
