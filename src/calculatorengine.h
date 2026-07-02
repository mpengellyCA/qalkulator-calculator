// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CalculatorEngine — the thin adapter that drives the single global libqalculate
// CALCULATOR on a dedicated worker thread. Calculate-as-you-type is sequence
// numbered and abortable: each new request bumps a counter, aborts any in-flight
// calculation, and stale results (tagged with an old sequence) are discarded.
//
// Threading model:
//   GUI thread            worker thread (CalcWorker moved onto m_thread)
//   ----------            --------------------------------------------
//   updateInput()  -----> evaluatePreview()   [locks calcMutex around calc]
//   commit()       -----> evaluateCommit()
//   updateConversion() -> evaluateConversion()
//   results come back via queued signals, dropped if seq is stale.
//
// The engine owns a QRecursiveMutex shared with CurrencyService: the worker locks
// it around every CALCULATOR->calculate*/calculateAndPrint call; CurrencyService
// locks it around loadExchangeRates()/definition reloads (network fetch stays
// outside the lock).

#pragma once

#include <QHash>
#include <QObject>
#include <QRecursiveMutex>
#include <QString>
#include <QStringList>
#include <QVariantList>

class ResultRegisterModel;
class QThread;
class CalcWorker;

class CalculatorEngine : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString livePreview READ livePreview NOTIFY livePreviewChanged)
    Q_PROPERTY(bool livePreviewError READ livePreviewError NOTIFY livePreviewChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY livePreviewChanged)
    Q_PROPERTY(bool calculating READ calculating NOTIFY calculatingChanged)
    Q_PROPERTY(QString ans READ ans NOTIFY ansChanged)

public:
    explicit CalculatorEngine(ResultRegisterModel *registerModel, QObject *parent = nullptr);
    ~CalculatorEngine() override;

    // Property getters
    QString livePreview() const { return m_livePreview; }
    bool livePreviewError() const { return m_livePreviewError; }
    QString errorMessage() const { return m_errorMessage; }
    bool calculating() const { return m_calculating; }
    QString ans() const { return m_ans; }

    // QML-facing API
    Q_INVOKABLE void updateInput(const QString &expr);
    Q_INVOKABLE void commit(const QString &expr);
    // Converters are per-view: `channel` identifies the caller (e.g. 0=units,
    // 1=currency) so each ConverterView only consumes its own result via the
    // conversionUpdated() signal. There is no shared conversion state.
    Q_INVOKABLE void updateConversion(const QString &amount, const QString &fromUnit, const QString &toUnit, bool isCurrency, int channel);
    Q_INVOKABLE QString ansToken() const;
    Q_INVOKABLE QStringList currencyCodes() const;
    // For the converter's history dropdown: the register entries usable as an
    // amount FROM `fromUnit` — a raw (dimensionless) number, or a quantity whose
    // unit is convertible to fromUnit (currencies inter-convert). Newest first.
    // Each map is {expression, value, amount} where `amount` is a clean,
    // re-parseable number expressed in `fromUnit`.
    Q_INVOKABLE QVariantList compatibleAmounts(const QString &fromUnit) const;
    Q_INVOKABLE void copyToClipboard(const QString &text);
    Q_INVOKABLE QString clipboardText() const;

    // Shared serialization lock for CurrencyService.
    QRecursiveMutex *calcMutex();

public Q_SLOTS:
    // Re-run the last preview so a settings change (format/precision/angle unit)
    // updates the live result instantly. QML/Config connects to this.
    void refreshFormatting();

Q_SIGNALS:
    void livePreviewChanged();
    void calculatingChanged();
    void ansChanged();
    void committed(bool ok, QString value);
    // Per-channel conversion result. `rate` is the raw "1 from -> to" value; the
    // view composes the full "1 <from> = <rate>" line. Only the view whose
    // channel matches consumes it.
    void conversionUpdated(int channel, QString result, QString rate, bool error);

    // Internal: GUI thread -> worker thread (queued).
    void requestPreview(quint64 seq, QString expr);
    void requestConversion(quint64 seq, int channel, QString expr, QString rateExpr);

private Q_SLOTS:
    // Worker thread -> GUI thread (queued).
    void onPreviewReady(quint64 seq, QString value, bool error, QString message);
    void onConversionReady(quint64 seq, int channel, QString result, QString rate, bool error);

private:
    void setCalculating(bool v);
    void setLivePreview(const QString &value, bool error, const QString &message);

    ResultRegisterModel *m_registerModel = nullptr;

    QThread *m_thread = nullptr;
    CalcWorker *m_worker = nullptr;
    mutable QRecursiveMutex m_calcMutex; // locked from const query methods too

    // Preview state
    QString m_livePreview;
    bool m_livePreviewError = false;
    QString m_errorMessage;
    bool m_calculating = false;
    quint64 m_previewSeq = 0;   // latest issued preview seq
    QString m_lastInput;        // for refreshFormatting()

    // Commit is a separate, non-abortable request stream from the as-you-type
    // preview. While a commit is in flight, updateInput() must NOT abort (that
    // would cancel the commit), and the committed expression is carried through
    // the result signal rather than read from m_lastInput (which the follow-up
    // clear overwrites).
    quint64 m_commitSeq = 0;
    int m_commitsInFlight = 0;  // GUI-thread only

    // Per-channel conversion sequence (stale-result dropping is independent per
    // channel); results are delivered via conversionUpdated(), not shared state.
    QHash<int, quint64> m_conversionSeq;

    QString m_ans;
};
