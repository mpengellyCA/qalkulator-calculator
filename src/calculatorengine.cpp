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

// Shared commit core: evaluate `expr` to a formatted result under the shared
// lock and update the session-wide `ans` variable. Returns success; fills
// *value (formatted result) and *message (drained calculator messages — the
// error text on failure, otherwise any warnings). Used by both the interactive
// commit and the MCP agent evaluation so they format identically.
bool computeExpression(QRecursiveMutex *mutex, const QString &expr, int timeoutMs, bool singleUnit, QString *value, QString *message)
{
    std::string out;
    bool ok = false;
    bool hadError = false;
    QString msg;
    {
        QMutexLocker<QRecursiveMutex> lock(mutex);
        CALCULATOR->clearMessages();
        EvaluationOptions eo = makeEvalOptions();
        if (singleUnit) {
            // Agent-friendly: a converted quantity as one unit ("3.106 mi"), not
            // libqalculate's default mixed units ("3 mi + 188 yd + 0.2 ft").
            eo.mixed_units_conversion = MIXED_UNITS_CONVERSION_NONE;
        }
        const PrintOptions po = makePrintOptions();

        MathStructure mstruct;
        ok = CALCULATOR->calculate(&mstruct, normalizeExpression(expr).toStdString(), timeoutMs, eo);
        msg = drainMessages(&hadError);
        if (ok && !CALCULATOR->aborted() && !hadError) {
            mstruct.format(po);
            out = mstruct.print(po);
            // Update the `ans` continuation variable with the raw result.
            Variable *existing = CALCULATOR->getVariable("ans");
            if (existing && existing->isKnown()) {
                static_cast<KnownVariable *>(existing)->set(mstruct);
            } else {
                CALCULATOR->addVariable(new KnownVariable(std::string(), "ans", mstruct, "Last Answer", false));
            }
        } else {
            ok = false;
        }
    }
    if (value) {
        *value = QString::fromStdString(out);
    }
    if (message) {
        *message = msg;
    }
    return ok;
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

    // Commit: evaluate, format+print, update `ans`, and hand back the value.
    void evaluateCommit(quint64 seq, const QString &expr)
    {
        QString value;
        const bool ok = computeExpression(m_mutex, expr, kCommitTimeoutMs, /*singleUnit=*/false, &value, nullptr);
        Q_EMIT commitReady(seq, expr, value, ok);
    }

    // MCP agent evaluation: same compute path as commit (so results format and
    // land in the tape identically, with proper error detection and `ans`
    // continuity), tagged with a caller-chosen id so the server can correlate the
    // async reply and carrying the message text for a real error string. Uses the
    // "to"/"->" conversion operators; the convert tool builds those explicitly.
    void evaluateAgent(quint64 id, const QString &expr)
    {
        QString value;
        QString message;
        const bool ok = computeExpression(m_mutex, expr, kCommitTimeoutMs, /*singleUnit=*/true, &value, &message);
        Q_EMIT agentReady(id, expr, value, ok, message);
    }

Q_SIGNALS:
    void previewReady(quint64 seq, QString value, bool error, QString message);
    void conversionReady(quint64 seq, int channel, QString result, QString info, bool error);
    void commitReady(quint64 seq, QString expr, QString value, bool ok);
    void agentReady(quint64 id, QString expr, QString value, bool ok, QString message);

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
    ++s_engineCount;

    // Format/precision/angle-unit changes must refresh THIS engine's live result
    // (each instance wires itself, so every window updates independently).
    for (auto sig : {&QalkulatorConfig::resultFormatChanged, &QalkulatorConfig::decimalPlacesChanged,
                     &QalkulatorConfig::thousandsSeparatorChanged, &QalkulatorConfig::angleUnitChanged}) {
        connect(QalkulatorConfig::self(), sig, this, &CalculatorEngine::refreshFormatting);
    }

    m_thread = new QThread(this);
    m_thread->setObjectName(QStringLiteral("QalKulatorCalcWorker"));
    m_worker = new CalcWorker(&sharedCalcMutex());
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

    // Agent (MCP) result handling: on success append to this instance's tape —
    // exactly like a commit, so the user watches the agent's math appear — then
    // report back to the server tagged with the correlation id.
    connect(m_worker, &CalcWorker::agentReady, this, [this](quint64 id, const QString &expr, const QString &value, bool ok, const QString &message) {
        if (ok) {
            m_registerModel->append(expr, value, QString());
            m_ans = value;
            Q_EMIT ansChanged();
        }
        Q_EMIT agentEvaluated(id, expr, value, ok, message);
    });

    m_thread->start();
}

CalculatorEngine::~CalculatorEngine()
{
    // Cancel any in-flight calculation and shut the worker thread down cleanly.
    if (CALCULATOR) {
        CALCULATOR->abort(); // unblock our worker if it is mid-evaluation
    }
    if (m_thread) {
        m_thread->quit();
        m_thread->wait();
    }
    // libqalculate keeps a persistent internal calculation thread alive for the
    // lifetime of the global CALCULATOR. Only the LAST engine tears it down —
    // otherwise destroying a secondary window's engine would kill it under the
    // engines that are still running.
    if (--s_engineCount == 0 && CALCULATOR) {
        CALCULATOR->terminateThreads();
    }
}

QRecursiveMutex &CalculatorEngine::sharedCalcMutex()
{
    // One lock guarding the single global CALCULATOR, shared by every engine +
    // worker and by CurrencyService. Function-local static: thread-safe init,
    // outlives every instance, never destroyed early.
    static QRecursiveMutex s_mutex;
    return s_mutex;
}

QRecursiveMutex *CalculatorEngine::calcMutex()
{
    return &sharedCalcMutex();
}

int CalculatorEngine::s_engineCount = 0;

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

void CalculatorEngine::evaluateForAgent(quint64 id, const QString &expr)
{
    // Serializes on the worker after any pending preview/commit; its own id
    // stream means it is never confused with the preview/commit sequences.
    QMetaObject::invokeMethod(m_worker, "evaluateAgent", Qt::QueuedConnection, Q_ARG(quint64, id), Q_ARG(QString, expr));
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

QString CalculatorEngine::clipboardText() const
{
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        return cb->text();
    }
    return QString();
}

QStringList CalculatorEngine::currencyCodes() const
{
    QStringList codes;
    QMutexLocker<QRecursiveMutex> lock(&sharedCalcMutex());
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

    QMutexLocker<QRecursiveMutex> lock(&sharedCalcMutex());

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

// Depth-first search for the first Unit referenced anywhere in a structure
// (a quantity is typically number × unit; compound units nest deeper).
static Unit *firstUnitIn(const MathStructure &m)
{
    if (m.isUnit()) {
        return m.unit();
    }
    for (size_t i = 0; i < m.size(); ++i) {
        if (Unit *u = firstUnitIn(m[i])) {
            return u;
        }
    }
    return nullptr;
}

QVariantMap CalculatorEngine::classifyAmount(const QString &value) const
{
    QVariantMap res;
    res.insert(QStringLiteral("kind"), QStringLiteral("number"));
    res.insert(QStringLiteral("unit"), QString());
    res.insert(QStringLiteral("unitName"), QString());
    res.insert(QStringLiteral("amount"), QString());

    const QString v = value.trimmed();
    if (v.isEmpty() || !CALCULATOR) {
        return res;
    }

    QMutexLocker<QRecursiveMutex> lock(&sharedCalcMutex());

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

    EvaluationOptions eo;
    PrintOptions po;
    po.use_unicode_signs = false;
    po.number_fraction_format = FRACTION_DECIMAL;
    static const QRegularExpression wsRe(QStringLiteral("\\s+"));

    CALCULATOR->clearMessages();
    MathStructure m;
    CALCULATOR->calculate(&m, v.toStdString(), 400, eo);
    if (CALCULATOR->aborted() || hadError()) {
        return res; // unparseable → caller falls back to the raw value
    }

    if (!m.containsType(STRUCT_UNIT)) {
        if (!m.representsNumber()) {
            return res;
        }
        QString amount = v;
        amount.remove(wsRe);
        res[QStringLiteral("amount")] = amount;
        return res; // kind stays "number"
    }

    Unit *u = firstUnitIn(m);
    const bool isCurrency = u && u->isCurrency();

    // Coefficient = value / (1 <abbreviation>), iff that cancels to a pure number
    // (true for a simple quantity; a compound unit like m/s leaves a residual
    // unit, so we fall back to an empty amount).
    QString amount;
    if (u) {
        const std::string ab = u->abbreviation(true, false);
        CALCULATOR->clearMessages();
        MathStructure ratio;
        const std::string testExpr = "(" + v.toStdString() + ")/(" + ab + ")";
        CALCULATOR->calculate(&ratio, testExpr, 400, eo);
        if (!CALCULATOR->aborted() && !hadError()
            && !ratio.containsType(STRUCT_UNIT) && ratio.representsNumber()) {
            ratio.format(po);
            amount = QString::fromStdString(ratio.print(po));
            amount.remove(wsRe);
        }
    }

    if (isCurrency) {
        res[QStringLiteral("kind")] = QStringLiteral("currency");
        res[QStringLiteral("unit")] = u ? QString::fromStdString(u->abbreviation(true, false)) : QString();
    } else {
        res[QStringLiteral("kind")] = QStringLiteral("unit");
        if (u) {
            res[QStringLiteral("unit")] = QString::fromStdString(u->abbreviation(true, false));
            res[QStringLiteral("unitName")] = QString::fromStdString(u->singular(true, false));
        }
    }
    res[QStringLiteral("amount")] = amount;
    return res;
}

#include "calculatorengine.moc"
