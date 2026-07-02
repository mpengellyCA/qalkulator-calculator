// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "currencyservice.h"

#include "calculatorengine.h"
#include "qalkulatorconfig.h"

#include <QDateTime>
#include <QMutexLocker>
#include <QRecursiveMutex>
#include <QThread>

#include <libqalculate/qalculate.h>

CurrencyService::CurrencyService(CalculatorEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    // Definitions + rates are loaded in main() before we are constructed, so the
    // locale's local currency is resolved by now. Record it, then apply any saved
    // override so "$"/bare-currency/unspecified conversions use the chosen unit.
    captureLocaleCurrency();
    applyLocalCurrency(QalkulatorConfig::self()->defaultCurrency());
}

CurrencyService::~CurrencyService()
{
    // If a blocking network fetch is still running at shutdown, detach our result
    // handler (so it can't touch a torn-down engine/CALCULATOR), then wait only
    // briefly so quitting never blocks the GUI for the full 15s network timeout.
    if (m_fetchThread) {
        disconnect(m_fetchThread, nullptr, this, nullptr);
        if (CALCULATOR) {
            CALCULATOR->abort();
        }
        if (m_fetchThread->wait(2000)) {
            delete m_fetchThread;
        }
        // Else: still downloading — do NOT delete a running QThread (that aborts).
        // The process is exiting; intentionally leak it and let the OS reap it.
        m_fetchThread = nullptr;
    }
}

QString CurrencyService::defaultCurrency() const
{
    return QalkulatorConfig::self()->defaultCurrency();
}

void CurrencyService::setDefaultCurrency(const QString &code)
{
    if (QalkulatorConfig::self()->defaultCurrency() == code) {
        return;
    }
    QalkulatorConfig::self()->setDefaultCurrency(code);
    QalkulatorConfig::self()->save();
    applyLocalCurrency(code);
    Q_EMIT defaultCurrencyChanged();
}

void CurrencyService::captureLocaleCurrency()
{
    QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
    if (Unit *u = CALCULATOR->getLocalCurrency()) {
        m_localeCurrency = QString::fromStdString(u->abbreviation(true, false));
    }
}

void CurrencyService::applyLocalCurrency(const QString &code)
{
    // Empty => restore the captured locale default. Re-resolve the Unit* by code
    // every time: a rate reload recreates the currency units, so cached pointers
    // would dangle.
    const QString target = code.isEmpty() ? m_localeCurrency : code;
    if (target.isEmpty()) {
        return;
    }
    QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
    for (Unit *u : CALCULATOR->units) {
        if (u && u->isCurrency() && QString::fromStdString(u->abbreviation(true, false)) == target) {
            CALCULATOR->setLocalCurrency(u);
            return;
        }
    }
}

void CurrencyService::setRefreshing(bool v)
{
    if (m_refreshing != v) {
        m_refreshing = v;
        Q_EMIT refreshingChanged();
    }
}

void CurrencyService::setAvailable(bool v)
{
    if (m_available != v) {
        m_available = v;
        Q_EMIT availableChanged();
    }
}

QString CurrencyService::formatUpdated(long long secs) const
{
    if (secs <= 0) {
        return {};
    }
    const QDateTime dt = QDateTime::fromSecsSinceEpoch(static_cast<qint64>(secs));
    return QStringLiteral("updated ") + dt.toString(QStringLiteral("yyyy-MM-dd"));
}

QStringList CurrencyService::collectCurrencies() const
{
    // Same logic as CalculatorEngine::currencyCodes(): sorted, common ones first.
    QStringList codes;
    {
        QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
        for (Unit *u : CALCULATOR->units) {
            if (u && u->isCurrency()) {
                const QString abbr = QString::fromStdString(u->abbreviation(true, false));
                if (!abbr.isEmpty() && !codes.contains(abbr)) {
                    codes << abbr;
                }
            }
        }
    }
    codes.sort(Qt::CaseInsensitive);

    static const QStringList kCommon = {
        QStringLiteral("USD"), QStringLiteral("EUR"), QStringLiteral("GBP"),
        QStringLiteral("JPY"), QStringLiteral("CAD"), QStringLiteral("AUD"),
        QStringLiteral("CHF"), QStringLiteral("CNY"),
    };
    QStringList hoisted;
    for (const QString &c : kCommon) {
        if (codes.removeOne(c)) {
            hoisted << c;
        }
    }
    return hoisted + codes;
}

void CurrencyService::syncFromCache()
{
    long long t = 0;
    {
        QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
        t = static_cast<long long>(CALCULATOR->getExchangeRatesTime());
    }
    const QString updated = formatUpdated(t);
    if (updated != m_lastUpdated) {
        m_lastUpdated = updated;
        Q_EMIT lastUpdatedChanged();
    }

    const QStringList codes = collectCurrencies();
    if (codes != m_currencies) {
        m_currencies = codes;
        Q_EMIT currenciesChanged();
    }

    // Rates are considered available if we have a currency list and a known time.
    setAvailable(!m_currencies.isEmpty());
}

void CurrencyService::refresh()
{
    if (m_refreshing) {
        return; // a fetch is already in flight
    }

    // Offline: keep last-known cache, just make sure currencies + lastUpdated are
    // populated, then bail without blocking. canFetch() reads CALCULATOR state, so
    // serialize it against the worker via the shared mutex.
    bool canFetch = false;
    {
        QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
        canFetch = CALCULATOR->canFetch();
    }
    if (!canFetch) {
        syncFromCache();
        return;
    }

    setRefreshing(true);

    // Blocking network call on a one-shot worker thread, OUTSIDE the engine mutex.
    // The result is carried back via a shared flag read on the GUI thread when the
    // thread's finished() signal fires (queued to this object's thread). The thread
    // is tracked in m_fetchThread so the destructor can wait it out on quit.
    auto *ok = new bool(false);
    m_fetchThread = QThread::create([ok] {
        // 15s timeout; fetch all currencies. Purely local to CALCULATOR's own
        // network layer — no engine mutex held here.
        *ok = CALCULATOR->fetchExchangeRates(15);
    });
    connect(m_fetchThread, &QThread::finished, this, [this, ok]() {
        // Clear our handle and dispose the thread FIRST: onFetchFinished() flips
        // m_refreshing, which can trigger a re-entrant refresh() — if m_fetchThread
        // still pointed here it would be overwritten and leaked.
        QThread *finished = m_fetchThread;
        m_fetchThread = nullptr;
        if (finished) {
            finished->deleteLater();
        }
        const bool okValue = *ok;
        delete ok;
        onFetchFinished(okValue);
    });
    m_fetchThread->start();
}

void CurrencyService::onFetchFinished(bool ok)
{
    if (ok) {
        // Reload the freshly-fetched rates into CALCULATOR under the shared lock.
        QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
        CALCULATOR->loadExchangeRates();
    }
    if (ok) {
        // loadExchangeRates recreates the currency units and re-resolves the local
        // currency from the locale, so re-apply any configured override.
        applyLocalCurrency(QalkulatorConfig::self()->defaultCurrency());
    }
    // Update currencies + lastUpdated + available from the (now current) cache.
    syncFromCache();
    setRefreshing(false);
}

void CurrencyService::refreshIfStale()
{
    // Populate from the already-loaded cache immediately (main.cpp loaded rates).
    syncFromCache();

    // checkExchangeRatesDate(7) returns TRUE when rates are current (<=7 days)
    // and FALSE when they need updating. Only refresh (in background) when online
    // AND stale. Both reads touch CALCULATOR, so serialize via the shared mutex.
    bool shouldRefresh = false;
    {
        QMutexLocker<QRecursiveMutex> lock(m_engine->calcMutex());
        shouldRefresh = CALCULATOR->canFetch() && !CALCULATOR->checkExchangeRatesDate(7);
    }
    if (shouldRefresh) {
        refresh();
    }
}
