// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "calculatorengine.h"

#include "qalkulatorconfig.h"
#include "resultregistermodel.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QThread>

#include <libqalculate/qalculate.h>

#include <algorithm>

namespace
{
// Evaluation timeout for calculate-as-you-type (ms). Kept short so heavy
// expressions don't stall the worker; the sequence discipline drops stale ones.
constexpr int kPreviewTimeoutMs = 5000;
constexpr int kCommitTimeoutMs = 10000;
constexpr int kConversionTimeoutMs = 5000;

// Thin natural-language normalization for the "X% of Y" idiom (spec §1/§3).
// libqalculate (and the reference qalc CLI) have no "of" operator, so the
// calculator idiom "12% of 340" is rewritten to multiplication "12% * 340".
// Scoped to the standalone word so it never touches identifiers/units.
QString normalizeExpression(const QString &expr)
{
    static const QRegularExpression ofRe(QStringLiteral("\\bof\\b"), QRegularExpression::CaseInsensitiveOption);
    QString out = expr;
    out.replace(ofRe, QStringLiteral("*"));
    return out;
}

// Build PrintOptions from the current QalkulatorConfig (resultFormat / decimalPlaces /
// thousandsSeparator).
PrintOptions makePrintOptions()
{
    PrintOptions po;
    po.use_unicode_signs = false; // keep output ASCII-parseable and predictable
    po.spacious = true;
    po.lower_case_e = false;
    // Show irrational/approximate results as a clean number (e.g. sqrt(2) ->
    // 1.4142136) rather than leaking interval arithmetic as "interval(...)".
    po.interval_display = INTERVAL_DISPLAY_SIGNIFICANT_DIGITS;

    const int format = QalkulatorConfig::self()->resultFormat();
    switch (format) {
    case 1: // scientific
        po.min_exp = EXP_SCIENTIFIC;
        po.exp_display = EXP_DEFAULT;
        break;
    case 2: // engineering
        po.min_exp = -3; // multiples of 3 -> engineering notation
        po.exp_display = EXP_DEFAULT;
        break;
    case 0: // normal
    default:
        po.min_exp = EXP_NONE;
        break;
    }

    const int decimals = QalkulatorConfig::self()->decimalPlaces();
    if (decimals >= 0) {
        po.use_max_decimals = true;
        po.max_decimals = decimals;
        po.use_min_decimals = true;
        po.min_decimals = decimals;
    } else {
        // Automatic precision.
        po.use_max_decimals = false;
        po.max_decimals = -1;
        po.use_min_decimals = false;
        po.min_decimals = 0;
    }

    po.digit_grouping = QalkulatorConfig::self()->thousandsSeparator() ? DIGIT_GROUPING_STANDARD : DIGIT_GROUPING_NONE;

    return po;
}

// Build EvaluationOptions from the current QalkulatorConfig (angleUnit).
EvaluationOptions makeEvalOptions()
{
    EvaluationOptions eo;
    eo.approximation = APPROXIMATION_TRY_EXACT;
    eo.parse_options.angle_unit = [] {
        switch (QalkulatorConfig::self()->angleUnit()) {
        case 1:
            return ANGLE_UNIT_RADIANS;
        case 2:
            return ANGLE_UNIT_GRADIANS;
        case 0:
        default:
            return ANGLE_UNIT_DEGREES;
        }
    }();
    return eo;
}

// Drain the CALCULATOR message queue into a single human-readable string.
// Returns whether any error-level message was present.
QString drainMessages(bool *hadError)
{
    QStringList msgs;
    bool err = false;
    while (CalculatorMessage *m = CALCULATOR->message()) {
        if (m->type() == MESSAGE_ERROR) {
            err = true;
        }
        msgs << QString::fromStdString(m->message());
        CALCULATOR->nextMessage();
    }
    if (hadError) {
        *hadError = err;
    }
    return msgs.join(QStringLiteral("; "));
}
} // namespace

// ---------------------------------------------------------------------------
// CalcWorker — lives on the worker thread; performs the actual libqalculate work.
// ---------------------------------------------------------------------------
class CalcWorker : public QObject
{
    Q_OBJECT
public:
    explicit CalcWorker(QRecursiveMutex *mutex)
        : m_mutex(mutex)
    {
    }

public Q_SLOTS:
    void evaluatePreview(quint64 seq, const QString &expr)
    {
        const std::string input = normalizeExpression(expr).toStdString();
        std::string out;
        bool error = false;
        QString message;
        {
            QMutexLocker<QRecursiveMutex> lock(m_mutex);
            CALCULATOR->clearMessages();
            const EvaluationOptions eo = makeEvalOptions();
            const PrintOptions po = makePrintOptions();
            out = CALCULATOR->calculateAndPrint(input, kPreviewTimeoutMs, eo, po);
            message = drainMessages(&error);
        }
        Q_EMIT previewReady(seq, QString::fromStdString(out), error, message);
    }

    void evaluateConversion(quint64 seq, int channel, const QString &expr, const QString &rateExpr)
    {
        std::string result;
        std::string info;
        bool error = false;
        {
            QMutexLocker<QRecursiveMutex> lock(m_mutex);
            CALCULATOR->clearMessages();
            EvaluationOptions eo = makeEvalOptions();
            // A converter wants a single value (e.g. "2.2046 lb"), not libqalculate's
            // default mixed units ("2 lb + 3.27 oz" / "365 d + 6 h").
            eo.mixed_units_conversion = MIXED_UNITS_CONVERSION_NONE;
            PrintOptions po = makePrintOptions();
            // Pretty unit output for conversions: "°C", "ft²", "µg" instead of the
            // ASCII "oC"/"ft^2". Still parseable for the Ctrl+← flow back to calc.
            po.use_unicode_signs = true;
            result = CALCULATOR->calculateAndPrint(normalizeExpression(expr).toStdString(), kConversionTimeoutMs, eo, po);
            bool convErr = false;
            drainMessages(&convErr);
            error = convErr || result.empty();

            if (!rateExpr.isEmpty()) {
                CALCULATOR->clearMessages();
                info = CALCULATOR->calculateAndPrint(rateExpr.toStdString(), kConversionTimeoutMs, eo, po);
                bool rateErr = false;
                drainMessages(&rateErr);
                if (rateErr) {
                    info.clear();
                }
            }
        }
        Q_EMIT conversionReady(seq, channel, QString::fromStdString(result), QString::fromStdString(info), error);
    }

    // Commit: evaluate to a MathStructure, format+print, and return both the
    // formatted value and the raw parse string used to set `ans`.
    void evaluateCommit(quint64 seq, const QString &expr)
    {
        std::string value;
        bool ok = false;
        {
            QMutexLocker<QRecursiveMutex> lock(m_mutex);
            CALCULATOR->clearMessages();
            const EvaluationOptions eo = makeEvalOptions();
            const PrintOptions po = makePrintOptions();

            MathStructure mstruct;
            ok = CALCULATOR->calculate(&mstruct, normalizeExpression(expr).toStdString(), kCommitTimeoutMs, eo);
            bool hadError = false;
            drainMessages(&hadError);
            if (ok && !CALCULATOR->aborted() && !hadError) {
                mstruct.format(po);
                value = mstruct.print(po);
                // Update the `ans` continuation variable with the raw result.
                Variable *existing = CALCULATOR->getVariable("ans");
                if (existing && existing->isKnown()) {
                    static_cast<KnownVariable *>(existing)->set(mstruct);
                } else {
                    // is_local=false: a volatile session variable that must never be
                    // written to the user's local definitions or collide with theirs.
                    CALCULATOR->addVariable(new KnownVariable(std::string(), "ans", mstruct, "Last Answer", false));
                }
            } else {
                ok = false;
            }
        }
        Q_EMIT commitReady(seq, expr, QString::fromStdString(value), ok);
    }

Q_SIGNALS:
    void previewReady(quint64 seq, QString value, bool error, QString message);
    void conversionReady(quint64 seq, int channel, QString result, QString info, bool error);
    void commitReady(quint64 seq, QString expr, QString value, bool ok);

private:
    QRecursiveMutex *m_mutex;
};

// ---------------------------------------------------------------------------
// CalculatorEngine
// ---------------------------------------------------------------------------
CalculatorEngine::CalculatorEngine(ResultRegisterModel *registerModel, QObject *parent)
    : QObject(parent)
    , m_registerModel(registerModel)
{
    qRegisterMetaType<quint64>("quint64");

    m_thread = new QThread(this);
    m_thread->setObjectName(QStringLiteral("QalKulatorCalcWorker"));
    m_worker = new CalcWorker(&m_calcMutex);
    m_worker->moveToThread(m_thread);

    // Ensure the worker is destroyed on the worker thread when it finishes.
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);

    // GUI -> worker (queued across threads).
    connect(this, &CalculatorEngine::requestPreview, m_worker, &CalcWorker::evaluatePreview);
    connect(this, &CalculatorEngine::requestConversion, m_worker, &CalcWorker::evaluateConversion);

    // worker -> GUI (queued across threads).
    connect(m_worker, &CalcWorker::previewReady, this, &CalculatorEngine::onPreviewReady);
    connect(m_worker, &CalcWorker::conversionReady, this, &CalculatorEngine::onConversionReady);

    // Commit result handling (inline lambda so we can drive the register + ans).
    connect(m_worker, &CalcWorker::commitReady, this, [this](quint64 seq, const QString &expr, const QString &value, bool ok) {
        Q_UNUSED(seq)
        // A commit is not superseded by later previews; always honor it.
        if (m_commitsInFlight > 0) {
            --m_commitsInFlight;
        }
        // Keep the busy indicator up if another commit is still running.
        setCalculating(m_commitsInFlight > 0);
        if (ok) {
            const QString context; // v1: no separate context tag on commit
            // Store the *original* entered expression (carried through the signal),
            // not m_lastInput — the post-commit clear overwrites m_lastInput.
            m_registerModel->append(expr, value, context);
            m_ans = value;
            Q_EMIT ansChanged();
            Q_EMIT committed(true, value);
        } else {
            Q_EMIT committed(false, QString());
        }
    });

    m_thread->start();
}

CalculatorEngine::~CalculatorEngine()
{
    // Cancel any in-flight calculation and shut the worker thread down cleanly.
    if (CALCULATOR) {
        CALCULATOR->abort();
    }
    if (m_thread) {
        m_thread->quit();
        m_thread->wait();
    }
    // libqalculate keeps a persistent internal calculation thread alive for the
    // lifetime of the global CALCULATOR. Since we never delete CALCULATOR, that
    // thread must be terminated explicitly or the process hangs at exit. The
    // worker above is already stopped, so nothing is mid-evaluation here.
    if (CALCULATOR) {
        CALCULATOR->terminateThreads();
    }
}

QRecursiveMutex *CalculatorEngine::calcMutex()
{
    return &m_calcMutex;
}

void CalculatorEngine::setCalculating(bool v)
{
    if (m_calculating != v) {
        m_calculating = v;
        Q_EMIT calculatingChanged();
    }
}

void CalculatorEngine::setLivePreview(const QString &value, bool error, const QString &message)
{
    m_livePreview = value;
    m_livePreviewError = error;
    m_errorMessage = message;
    Q_EMIT livePreviewChanged();
}

void CalculatorEngine::updateInput(const QString &expr)
{
    m_lastInput = expr;

    if (expr.trimmed().isEmpty()) {
        // Clear preview immediately; drop any in-flight preview via a new seq.
        // Do NOT abort while a commit is in flight — that would cancel it (this
        // path is exactly the post-commit clear from the expression field).
        ++m_previewSeq;
        if (m_commitsInFlight == 0 && CALCULATOR) {
            CALCULATOR->abort();
        }
        setCalculating(m_commitsInFlight > 0);
        setLivePreview(QString(), false, QString());
        return;
    }

    const quint64 seq = ++m_previewSeq;
    // Cancel any *preview* currently running on the worker so it returns fast —
    // but never while a commit is running (it serializes ahead on the worker and
    // must not be aborted).
    if (m_commitsInFlight == 0 && CALCULATOR) {
        CALCULATOR->abort();
    }
    setCalculating(true);
    Q_EMIT requestPreview(seq, expr);
}

void CalculatorEngine::commit(const QString &expr)
{
    const QString e = expr.trimmed().isEmpty() ? m_lastInput : expr;
    m_lastInput = e;
    if (e.trimmed().isEmpty()) {
        Q_EMIT committed(false, QString());
        return;
    }
    setCalculating(true);
    // Commit runs on the worker; invoke directly (queued) so it serializes after
    // any pending preview. It uses its own sequence stream (never m_previewSeq) and
    // is guarded against abort by m_commitsInFlight so the follow-up updateInput("")
    // clear cannot cancel it.
    ++m_commitsInFlight;
    QMetaObject::invokeMethod(m_worker, "evaluateCommit", Qt::QueuedConnection, Q_ARG(quint64, ++m_commitSeq), Q_ARG(QString, e));
}

void CalculatorEngine::updateConversion(const QString &amount, const QString &fromUnit, const QString &toUnit, bool isCurrency, int channel)
{
    Q_UNUSED(isCurrency)

    if (amount.trimmed().isEmpty() || fromUnit.isEmpty() || toUnit.isEmpty()) {
        ++m_conversionSeq[channel];
        if (CALCULATOR) {
            CALCULATOR->abort();
        }
        // Clear this channel's view.
        Q_EMIT conversionUpdated(channel, QString(), QString(), false);
        return;
    }

    // "<amount> <from> to <to>" — libqalculate parses this natural form for both
    // units and currencies.
    const QString expr = amount + QStringLiteral(" ") + fromUnit + QStringLiteral(" to ") + toUnit;
    // Raw rate: "1 <from> to <to>" -> e.g. "0.9213 EUR"; the view composes the
    // full "1 <from> = 0.9213 EUR" line so no shared "from" state is needed.
    const QString rateExpr = QStringLiteral("1 ") + fromUnit + QStringLiteral(" to ") + toUnit;

    const quint64 seq = ++m_conversionSeq[channel];
    if (CALCULATOR) {
        CALCULATOR->abort();
    }
    Q_EMIT requestConversion(seq, channel, expr, rateExpr);
}

void CalculatorEngine::onPreviewReady(quint64 seq, QString value, bool error, QString message)
{
    if (seq != m_previewSeq) {
        return; // stale: a newer input superseded this one
    }
    setCalculating(false);

    // libqalculate returns the echoed input for many "not yet meaningful" cases;
    // treat an error-level message as the authoritative error signal.
    if (error) {
        const QString msg = message.isEmpty() ? QStringLiteral("Cannot evaluate expression") : message;
        setLivePreview(value, true, msg);
    } else {
        setLivePreview(value, false, QString());
    }
}

void CalculatorEngine::onConversionReady(quint64 seq, int channel, QString result, QString rate, bool error)
{
    if (seq != m_conversionSeq.value(channel)) {
        return; // stale conversion for this channel
    }
    // Deliver to the requesting view only; it owns its own result state.
    Q_EMIT conversionUpdated(channel, result, rate, error);
}

QString CalculatorEngine::ansToken() const
{
    return QStringLiteral("ans");
}

void CalculatorEngine::refreshFormatting()
{
    // Re-run the last preview under the new formatting options so QML updates
    // instantly. If there is nothing pending, do nothing.
    if (!m_lastInput.trimmed().isEmpty()) {
        updateInput(m_lastInput);
    }
}

void CalculatorEngine::copyToClipboard(const QString &text)
{
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
    }
}

QStringList CalculatorEngine::currencyCodes() const
{
    QStringList codes;
    QMutexLocker<QRecursiveMutex> lock(&m_calcMutex);
    for (Unit *u : CALCULATOR->units) {
        if (u && u->isCurrency()) {
            const QString abbr = QString::fromStdString(u->abbreviation(true, false));
            if (!abbr.isEmpty() && !codes.contains(abbr)) {
                codes << abbr;
            }
        }
    }
    lock.unlock();

    codes.sort(Qt::CaseInsensitive);

    // Hoist common currencies to the front (in the given priority order).
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

QVariantList CalculatorEngine::compatibleAmounts(const QString &fromUnit) const
{
    QVariantList out;
    const QString from = fromUnit.trimmed();
    if (!m_registerModel || from.isEmpty() || !CALCULATOR) {
        return out;
    }

    QMutexLocker<QRecursiveMutex> lock(&m_calcMutex);

    // Drain the message queue after a calculation, noting whether it errored.
    auto hadError = []() -> bool {
        bool err = false;
        while (CalculatorMessage *m = CALCULATOR->message()) {
            if (m->type() == MESSAGE_ERROR) {
                err = true;
            }
            CALCULATOR->nextMessage();
        }
        return err;
    };

    const std::string U = from.toStdString();
    EvaluationOptions eo;
    PrintOptions po;
    po.use_unicode_signs = false;
    po.number_fraction_format = FRACTION_DECIMAL; // never emit "8001/5000" as an amount

    static const QRegularExpression wsRe(QStringLiteral("\\s+"));

    for (int i = m_registerModel->count() - 1; i >= 0; --i) { // newest first
        const QString value = m_registerModel->valueAt(i);
        const QString expression = m_registerModel->expressionAt(i);
        if (value.trimmed().isEmpty()) {
            continue;
        }

        CALCULATOR->clearMessages();
        MathStructure m;
        CALCULATOR->calculate(&m, value.toStdString(), 400, eo);
        if (CALCULATOR->aborted() || hadError()) {
            continue;
        }

        QString amount;
        if (!m.containsType(STRUCT_UNIT)) {
            // Dimensionless → a raw number, usable as an amount as-is.
            if (!m.representsNumber()) {
                continue; // skip symbols / booleans / undefined
            }
            amount = value;
            amount.remove(wsRe); // strip digit-grouping so it re-parses cleanly
        } else {
            // Carries a unit → usable iff value / (1 fromUnit) is dimensionless
            // (same physical dimension; currencies cancel via the exchange rate).
            CALCULATOR->clearMessages();
            MathStructure ratio;
            const std::string testExpr = "(" + value.toStdString() + ")/(" + U + ")";
            CALCULATOR->calculate(&ratio, testExpr, 400, eo);
            if (CALCULATOR->aborted() || hadError()
                || ratio.containsType(STRUCT_UNIT) || !ratio.representsNumber()) {
                continue;
            }
            ratio.format(po);
            amount = QString::fromStdString(ratio.print(po));
            amount.remove(wsRe);
        }

        if (amount.isEmpty()) {
            continue;
        }

        QVariantMap row;
        row.insert(QStringLiteral("expression"), expression);
        row.insert(QStringLiteral("value"), value);
        row.insert(QStringLiteral("amount"), amount);
        out.append(row);
    }
    return out;
}

#include "calculatorengine.moc"
