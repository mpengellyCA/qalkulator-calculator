// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "mcpserver.h"

#include "calculatorengine.h"
#include "qalkulatorconfig.h"
#include "resultregistermodel.h"
#include "windowmanager.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QTcpServer>
#include <QTcpSocket>

#ifndef QALKULATOR_VERSION
#define QALKULATOR_VERSION "0.0.0-dev"
#endif

namespace
{
// MCP revision we advertise when the client doesn't request one.
constexpr const char *kDefaultProtocol = "2025-06-18";

QString reasonPhrase(int status)
{
    switch (status) {
    case 200: return QStringLiteral("OK");
    case 202: return QStringLiteral("Accepted");
    case 400: return QStringLiteral("Bad Request");
    case 401: return QStringLiteral("Unauthorized");
    case 404: return QStringLiteral("Not Found");
    case 405: return QStringLiteral("Method Not Allowed");
    default: return QStringLiteral("Internal Server Error");
    }
}

QJsonObject rpcError(const QJsonValue &id, int code, const QString &message)
{
    return QJsonObject{
        {QStringLiteral("jsonrpc"), QStringLiteral("2.0")},
        {QStringLiteral("id"), id.isUndefined() ? QJsonValue(QJsonValue::Null) : id},
        {QStringLiteral("error"), QJsonObject{{QStringLiteral("code"), code}, {QStringLiteral("message"), message}}},
    };
}

QJsonObject rpcResult(const QJsonValue &id, const QJsonValue &result)
{
    return QJsonObject{
        {QStringLiteral("jsonrpc"), QStringLiteral("2.0")},
        {QStringLiteral("id"), id.isUndefined() ? QJsonValue(QJsonValue::Null) : id},
        {QStringLiteral("result"), result},
    };
}

// Wrap plain text as an MCP tool result (content blocks + isError flag).
QJsonObject toolResult(const QString &text, bool isError)
{
    return QJsonObject{
        {QStringLiteral("content"), QJsonArray{QJsonObject{{QStringLiteral("type"), QStringLiteral("text")}, {QStringLiteral("text"), text}}}},
        {QStringLiteral("isError"), isError},
    };
}
} // namespace

McpServer::McpServer(WindowManager *windows, QObject *parent)
    : QObject(parent)
    , m_windows(windows)
{
    if (enabled()) {
        start();
    }
}

McpServer::~McpServer()
{
    stop();
}

// --- Config-backed state ---------------------------------------------------

bool McpServer::enabled() const
{
    return QalkulatorConfig::self()->mcpEnabled();
}

bool McpServer::running() const
{
    return m_server && m_server->isListening();
}

int McpServer::port() const
{
    return running() ? m_boundPort : QalkulatorConfig::self()->mcpPort();
}

QString McpServer::token() const
{
    return QalkulatorConfig::self()->mcpToken();
}

QString McpServer::url() const
{
    return QStringLiteral("http://127.0.0.1:%1/mcp").arg(port());
}

QString McpServer::bridgeCommand() const
{
    // Prefer the bridge sitting next to the running executable; fall back to the
    // bare name (found on PATH once installed).
    QString name = QStringLiteral("qalkulator-mcp");
#ifdef Q_OS_WIN
    name += QStringLiteral(".exe");
#endif
    const QString local = QDir(QCoreApplication::applicationDirPath()).filePath(name);
    return QFileInfo::exists(local) ? local : name;
}

void McpServer::ensureToken()
{
    if (QalkulatorConfig::self()->mcpToken().isEmpty()) {
        QByteArray raw(16, Qt::Uninitialized);
        QRandomGenerator::system()->generate(raw.begin(), raw.end());
        QalkulatorConfig::self()->setMcpToken(QString::fromLatin1(raw.toHex()));
        QalkulatorConfig::self()->save();
    }
}

void McpServer::setEnabled(bool on)
{
    if (on == enabled() && (on == running())) {
        return;
    }
    QalkulatorConfig::self()->setMcpEnabled(on);
    if (on) {
        ensureToken();
        QalkulatorConfig::self()->save();
        start();
    } else {
        QalkulatorConfig::self()->save();
        stop();
    }
    Q_EMIT stateChanged();
}

void McpServer::regenerateToken()
{
    QByteArray raw(16, Qt::Uninitialized);
    QRandomGenerator::system()->generate(raw.begin(), raw.end());
    QalkulatorConfig::self()->setMcpToken(QString::fromLatin1(raw.toHex()));
    QalkulatorConfig::self()->save();
    Q_EMIT stateChanged();
}

void McpServer::copyText(const QString &text) const
{
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
    }
}

// --- Listener lifecycle ----------------------------------------------------

void McpServer::start()
{
    if (running()) {
        return;
    }
    ensureToken();
    if (!m_server) {
        m_server = new QTcpServer(this);
        connect(m_server, &QTcpServer::newConnection, this, &McpServer::onNewConnection);
    }
    // Try the configured port, then a small range, so a stale listener elsewhere
    // doesn't make the feature silently unavailable.
    const int desired = QalkulatorConfig::self()->mcpPort();
    for (int p = desired; p <= desired + 9; ++p) {
        if (m_server->listen(QHostAddress::LocalHost, static_cast<quint16>(p))) {
            m_boundPort = p;
            break;
        }
    }
    if (!running()) {
        qWarning("McpServer: could not bind loopback port %d-%d", desired, desired + 9);
    }
    Q_EMIT stateChanged();
}

void McpServer::stop()
{
    // Close every agent window: snapshot + clear first so the windows' onClosing
    // (which calls endSession) sees an empty map and is a harmless no-op.
    const QList<CalcInstance *> insts = m_sessions.values();
    m_sessions.clear();
    m_pending.clear();
    for (CalcInstance *inst : insts) {
        Q_EMIT closeAgentWindowRequested(inst);
    }

    if (m_server) {
        m_server->close();
        for (auto it = m_buffers.constBegin(); it != m_buffers.constEnd(); ++it) {
            it.key()->deleteLater();
        }
        m_buffers.clear();
    }
    Q_EMIT sessionCountChanged();
    Q_EMIT stateChanged();
}

void McpServer::endSession(CalcInstance *inst)
{
    const QString key = m_sessions.key(inst);
    if (key.isEmpty()) {
        return; // already gone (e.g. torn down by the server side)
    }
    m_sessions.remove(key);
    Q_EMIT sessionCountChanged();
}

// --- HTTP plumbing ---------------------------------------------------------

void McpServer::onNewConnection()
{
    while (m_server && m_server->hasPendingConnections()) {
        QTcpSocket *sock = m_server->nextPendingConnection();
        m_buffers.insert(sock, QByteArray());
        connect(sock, &QTcpSocket::readyRead, this, [this, sock]() { onReadyRead(sock); });
        connect(sock, &QTcpSocket::disconnected, this, [this, sock]() {
            m_buffers.remove(sock);
            sock->deleteLater();
        });
    }
}

void McpServer::onReadyRead(QTcpSocket *sock)
{
    if (!m_buffers.contains(sock)) {
        return;
    }
    m_buffers[sock].append(sock->readAll());

    // Drain as many complete HTTP requests as the buffer holds (keep-alive).
    for (;;) {
        QByteArray &buf = m_buffers[sock];
        const int headerEnd = buf.indexOf("\r\n\r\n");
        if (headerEnd < 0) {
            return; // headers still incoming
        }
        const QByteArray header = buf.left(headerEnd);
        const QList<QByteArray> lines = header.split('\n');
        if (lines.isEmpty()) {
            sock->close();
            return;
        }
        const QList<QByteArray> requestLine = lines.first().trimmed().split(' ');
        const QString method = QString::fromUtf8(requestLine.value(0).trimmed());
        const QString path = QString::fromUtf8(requestLine.value(1).trimmed());

        QHash<QString, QString> headers;
        for (int i = 1; i < lines.size(); ++i) {
            const QByteArray line = lines.at(i).trimmed();
            const int colon = line.indexOf(':');
            if (colon > 0) {
                headers.insert(QString::fromUtf8(line.left(colon)).trimmed().toLower(), QString::fromUtf8(line.mid(colon + 1)).trimmed());
            }
        }

        const int contentLength = headers.value(QStringLiteral("content-length")).toInt();
        const int total = headerEnd + 4 + contentLength;
        if (buf.size() < total) {
            return; // body still incoming
        }
        const QByteArray body = buf.mid(headerEnd + 4, contentLength);
        buf.remove(0, total);

        handleRequest(sock, method, path, headers, body);
    }
}

void McpServer::handleRequest(QTcpSocket *sock, const QString &method, const QString &path, const QHash<QString, QString> &headers, const QByteArray &body)
{
    Q_UNUSED(path)

    // Session teardown: the agent (or its host) closes the session.
    if (method == QLatin1String("DELETE")) {
        const QString sid = headers.value(QStringLiteral("mcp-session-id"));
        if (CalcInstance *inst = m_sessions.value(sid)) {
            m_sessions.remove(sid);
            Q_EMIT closeAgentWindowRequested(inst);
            Q_EMIT sessionCountChanged();
        }
        sendEmpty(sock, 200);
        return;
    }

    // We do not offer a server->client SSE stream; only POSTed request/response.
    if (method != QLatin1String("POST")) {
        sendEmpty(sock, 405, QStringLiteral("Allow: POST, DELETE"));
        return;
    }

    // Token gate (loopback is not enough — any local process could connect).
    const QString expected = token();
    const QString auth = headers.value(QStringLiteral("authorization"));
    const QString headerToken = headers.value(QStringLiteral("x-qalkulator-token"));
    const bool bearerOk = auth == QStringLiteral("Bearer ") + expected;
    const bool tokenOk = !expected.isEmpty() && (bearerOk || headerToken == expected);
    if (!tokenOk) {
        sendEmpty(sock, 401, QStringLiteral("WWW-Authenticate: Bearer"));
        return;
    }

    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        sendJson(sock, 400, rpcError(QJsonValue(QJsonValue::Null), -32700, QStringLiteral("Parse error")));
        return;
    }

    dispatch(sock, doc.object(), headers.value(QStringLiteral("mcp-session-id")));
}

void McpServer::sendJson(QTcpSocket *sock, int status, const QJsonObject &obj, const QString &sessionId)
{
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    QByteArray resp;
    resp += "HTTP/1.1 " + QByteArray::number(status) + ' ' + reasonPhrase(status).toUtf8() + "\r\n";
    resp += "Content-Type: application/json\r\n";
    resp += "Content-Length: " + QByteArray::number(payload.size()) + "\r\n";
    if (!sessionId.isEmpty()) {
        resp += "Mcp-Session-Id: " + sessionId.toUtf8() + "\r\n";
    }
    resp += "Connection: keep-alive\r\n\r\n";
    resp += payload;
    if (sock && sock->state() == QAbstractSocket::ConnectedState) {
        sock->write(resp);
        sock->flush();
    }
}

void McpServer::sendEmpty(QTcpSocket *sock, int status, const QString &extraHeader)
{
    QByteArray resp;
    resp += "HTTP/1.1 " + QByteArray::number(status) + ' ' + reasonPhrase(status).toUtf8() + "\r\n";
    resp += "Content-Length: 0\r\n";
    if (!extraHeader.isEmpty()) {
        resp += extraHeader.toUtf8() + "\r\n";
    }
    resp += "Connection: keep-alive\r\n\r\n";
    if (sock && sock->state() == QAbstractSocket::ConnectedState) {
        sock->write(resp);
        sock->flush();
    }
}

// --- JSON-RPC dispatch -----------------------------------------------------

void McpServer::dispatch(QTcpSocket *sock, const QJsonObject &req, const QString &sessionId)
{
    const QString rpcMethod = req.value(QStringLiteral("method")).toString();
    const QJsonValue id = req.value(QStringLiteral("id"));
    const QJsonObject params = req.value(QStringLiteral("params")).toObject();
    const bool isNotification = !req.contains(QStringLiteral("id"));

    // Notifications (initialized, cancelled, …) get an ack with no body.
    if (isNotification || rpcMethod.startsWith(QStringLiteral("notifications/"))) {
        sendEmpty(sock, 202);
        return;
    }

    if (rpcMethod == QLatin1String("initialize")) {
        const QString requested = params.value(QStringLiteral("protocolVersion")).toString();
        const QString agentName = params.value(QStringLiteral("clientInfo")).toObject().value(QStringLiteral("name")).toString(QStringLiteral("AI agent"));

        // New session -> new read-only agent window bound to its own instance.
        QByteArray raw(12, Qt::Uninitialized);
        QRandomGenerator::system()->generate(raw.begin(), raw.end());
        const QString newSession = QString::fromLatin1(raw.toHex());

        CalcInstance *inst = m_windows->createAgentInstance(agentName);
        connect(inst->engine(), &CalculatorEngine::agentEvaluated, this, &McpServer::onAgentEvaluated);
        m_sessions.insert(newSession, inst);
        Q_EMIT openAgentWindowRequested(inst);
        Q_EMIT sessionCountChanged();

        const QJsonObject result{
            {QStringLiteral("protocolVersion"), requested.isEmpty() ? QString::fromLatin1(kDefaultProtocol) : requested},
            {QStringLiteral("capabilities"), QJsonObject{{QStringLiteral("tools"), QJsonObject{}}}},
            {QStringLiteral("serverInfo"), QJsonObject{{QStringLiteral("name"), QStringLiteral("qalkulator")}, {QStringLiteral("version"), QStringLiteral(QALKULATOR_VERSION)}}},
            {QStringLiteral("instructions"),
             QStringLiteral("QalKulator exposes the Qalculate! engine. Each session has opened a read-only window the user is watching; "
                            "use `calculate` for expressions (units, constants, functions, percentages) and `convert` for unit/currency "
                            "conversions. Everything you compute is shown to the user in that window.")},
        };
        sendJson(sock, 200, rpcResult(id, result), newSession);
        return;
    }

    if (rpcMethod == QLatin1String("ping")) {
        sendJson(sock, 200, rpcResult(id, QJsonObject{}));
        return;
    }

    if (rpcMethod == QLatin1String("tools/list")) {
        const QJsonObject noArgs{{QStringLiteral("type"), QStringLiteral("object")}, {QStringLiteral("properties"), QJsonObject{}}};
        const QJsonArray tools{
            QJsonObject{
                {QStringLiteral("name"), QStringLiteral("calculate")},
                {QStringLiteral("description"),
                 QStringLiteral("Evaluate a mathematical expression with the Qalculate! engine. Supports units, physical "
                                "constants, functions and percentages, e.g. \"2+2\", \"sqrt(2)\", \"200 + 15%\", \"(3+4)^2\". "
                                "For unit or currency conversions use the \"to\" (or \"->\") operator, e.g. \"5 km to miles\", "
                                "\"c to km/s\", \"100 USD to EUR\" — or the dedicated `convert` tool. The expression and result "
                                "appear in the user's calculator window.")},
                {QStringLiteral("inputSchema"),
                 QJsonObject{{QStringLiteral("type"), QStringLiteral("object")},
                             {QStringLiteral("properties"),
                              QJsonObject{{QStringLiteral("expression"),
                                           QJsonObject{{QStringLiteral("type"), QStringLiteral("string")},
                                                       {QStringLiteral("description"), QStringLiteral("The expression to evaluate.")}}}}},
                             {QStringLiteral("required"), QJsonArray{QStringLiteral("expression")}}}},
            },
            QJsonObject{
                {QStringLiteral("name"), QStringLiteral("convert")},
                {QStringLiteral("description"),
                 QStringLiteral("Convert a quantity between units or currencies, e.g. value \"100\" from \"USD\" to \"EUR\", or "
                                "value \"5\" from \"km\" to \"mi\". The conversion appears in the user's calculator window.")},
                {QStringLiteral("inputSchema"),
                 QJsonObject{{QStringLiteral("type"), QStringLiteral("object")},
                             {QStringLiteral("properties"),
                              QJsonObject{
                                  {QStringLiteral("value"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")}, {QStringLiteral("description"), QStringLiteral("The amount to convert (a number as a string).")}}},
                                  {QStringLiteral("from"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")}, {QStringLiteral("description"), QStringLiteral("Source unit or currency code.")}}},
                                  {QStringLiteral("to"), QJsonObject{{QStringLiteral("type"), QStringLiteral("string")}, {QStringLiteral("description"), QStringLiteral("Target unit or currency code.")}}}}},
                             {QStringLiteral("required"), QJsonArray{QStringLiteral("value"), QStringLiteral("from"), QStringLiteral("to")}}}},
            },
            QJsonObject{
                {QStringLiteral("name"), QStringLiteral("get_history")},
                {QStringLiteral("description"), QStringLiteral("Return the calculations performed in this session so far (expression and result for each).")},
                {QStringLiteral("inputSchema"), noArgs},
            },
            QJsonObject{
                {QStringLiteral("name"), QStringLiteral("clear")},
                {QStringLiteral("description"), QStringLiteral("Clear the calculation history shown in the user's window.")},
                {QStringLiteral("inputSchema"), noArgs},
            },
        };
        sendJson(sock, 200, rpcResult(id, QJsonObject{{QStringLiteral("tools"), tools}}));
        return;
    }

    if (rpcMethod == QLatin1String("tools/call")) {
        CalcInstance *inst = m_sessions.value(sessionId);
        if (!inst) {
            sendJson(sock, 200, rpcError(id, -32001, QStringLiteral("No active MCP session; call initialize first.")));
            return;
        }
        const QString name = params.value(QStringLiteral("name")).toString();
        const QJsonObject args = params.value(QStringLiteral("arguments")).toObject();

        if (name == QLatin1String("calculate") || name == QLatin1String("convert")) {
            QString expr;
            if (name == QLatin1String("calculate")) {
                expr = args.value(QStringLiteral("expression")).toString().trimmed();
            } else {
                const QJsonValue v = args.value(QStringLiteral("value"));
                const QString value = v.isString() ? v.toString() : (v.isDouble() ? QString::number(v.toDouble(), 'g', 15) : QString());
                const QString from = args.value(QStringLiteral("from")).toString().trimmed();
                const QString to = args.value(QStringLiteral("to")).toString().trimmed();
                if (!value.trimmed().isEmpty() && !from.isEmpty() && !to.isEmpty()) {
                    expr = value.trimmed() + QLatin1Char(' ') + from + QStringLiteral(" to ") + to;
                }
            }
            if (expr.isEmpty()) {
                sendJson(sock, 200, rpcResult(id, toolResult(QStringLiteral("Missing or empty arguments."), true)));
                return;
            }
            const quint64 evalId = m_nextEvalId++;
            m_pending.insert(evalId, Pending{QPointer<QTcpSocket>(sock), id});
            inst->engine()->evaluateForAgent(evalId, expr);
            return; // reply deferred until agentEvaluated()
        }

        if (name == QLatin1String("clear")) {
            inst->history()->clear();
            sendJson(sock, 200, rpcResult(id, toolResult(QStringLiteral("Cleared the calculation history."), false)));
            return;
        }

        if (name == QLatin1String("get_history")) {
            ResultRegisterModel *h = inst->history();
            QJsonArray entries;
            QStringList lines;
            for (int i = 0; i < h->count(); ++i) {
                const QString e = h->expressionAt(i);
                const QString v = h->valueAt(i);
                entries.append(QJsonObject{{QStringLiteral("expression"), e}, {QStringLiteral("result"), v}});
                lines << (e + QStringLiteral(" = ") + v);
            }
            const QString text = lines.isEmpty() ? QStringLiteral("No calculations yet.") : lines.join(QLatin1Char('\n'));
            QJsonObject result = toolResult(text, false);
            result.insert(QStringLiteral("structuredContent"), QJsonObject{{QStringLiteral("entries"), entries}});
            sendJson(sock, 200, rpcResult(id, result));
            return;
        }

        sendJson(sock, 200, rpcError(id, -32602, QStringLiteral("Unknown tool: ") + name));
        return;
    }

    sendJson(sock, 200, rpcError(id, -32601, QStringLiteral("Method not found: ") + rpcMethod));
}

QString McpServer::toolResultText(bool ok, const QString &value, const QString &message) const
{
    if (ok) {
        return value;
    }
    return message.isEmpty() ? QStringLiteral("Could not evaluate the expression.") : message;
}

void McpServer::onAgentEvaluated(quint64 id, QString expr, QString value, bool ok, QString message)
{
    Q_UNUSED(expr)
    if (!m_pending.contains(id)) {
        return;
    }
    const Pending p = m_pending.take(id);
    if (p.sock.isNull()) {
        return; // client disconnected before we could answer
    }
    sendJson(p.sock, 200, rpcResult(p.rpcId, toolResult(toolResultText(ok, value, message), !ok)));
}
