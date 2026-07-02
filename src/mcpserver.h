// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// McpServer — a minimal Model Context Protocol server that lets an AI agent drive
// the Qalculate! engine while the user watches. It speaks JSON-RPC 2.0 over a
// hand-rolled HTTP/1.1 endpoint on the loopback interface (no extra Qt module
// needed beyond Qt::Network), guarded by a shared token.
//
// Each MCP session (one `initialize`) spawns a dedicated, read-only agent window
// bound to its own CalcInstance: every `calculate`/`convert` the agent performs
// is evaluated on that instance's engine and appended to its tape, so the user
// sees the full working. Closing the window ends the session; ending the session
// closes the window.
//
// Transport is MCP "Streamable HTTP" reduced to its request/response core: the
// server replies to each POSTed JSON-RPC message with a single JSON response
// (async tool calls are parked and answered when the engine returns). A thin
// stdio bridge (qalkulator-mcp) relays newline-delimited JSON to this endpoint
// for clients that only speak stdio.

#pragma once

#include <QByteArray>
#include <QHash>
#include <QJsonValue>
#include <QObject>
#include <QPointer>
#include <QString>

// Full type: used as a signal argument and dereferenced for engine access.
#include "calcinstance.h"

class WindowManager;
class QTcpServer;
class QTcpSocket;
class QJsonObject;

class McpServer : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled NOTIFY stateChanged)
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(int port READ port NOTIFY stateChanged)
    Q_PROPERTY(QString token READ token NOTIFY stateChanged)
    Q_PROPERTY(QString url READ url NOTIFY stateChanged)
    Q_PROPERTY(QString bridgeCommand READ bridgeCommand NOTIFY stateChanged)
    Q_PROPERTY(int sessionCount READ sessionCount NOTIFY sessionCountChanged)

public:
    explicit McpServer(WindowManager *windows, QObject *parent = nullptr);
    ~McpServer() override;

    bool enabled() const;
    bool running() const;
    int port() const;
    QString token() const;
    QString url() const;
    QString bridgeCommand() const;
    int sessionCount() const { return static_cast<int>(m_sessions.size()); }

    // Persist the on/off choice and start/stop the listener. Generates a token
    // on first enable.
    Q_INVOKABLE void setEnabled(bool on);
    // Rotate the shared secret (invalidates existing client configs).
    Q_INVOKABLE void regenerateToken();
    Q_INVOKABLE void copyText(const QString &text) const;
    // Called from QML when the user closes an agent window: drop its session so
    // further calls from that agent are rejected.
    Q_INVOKABLE void endSession(CalcInstance *inst);

Q_SIGNALS:
    void stateChanged();
    void sessionCountChanged();
    // C++ -> QML: open / close the agent's read-only window for this instance.
    void openAgentWindowRequested(CalcInstance *inst);
    void closeAgentWindowRequested(CalcInstance *inst);

private Q_SLOTS:
    void onNewConnection();
    void onAgentEvaluated(quint64 id, QString expr, QString value, bool ok, QString message);

private:
    void start();
    void stop();
    void ensureToken();

    // HTTP plumbing.
    void onReadyRead(QTcpSocket *sock);
    void handleRequest(QTcpSocket *sock, const QString &method, const QString &path, const QHash<QString, QString> &headers, const QByteArray &body);
    void sendJson(QTcpSocket *sock, int status, const QJsonObject &obj, const QString &sessionId = QString());
    void sendEmpty(QTcpSocket *sock, int status, const QString &extraHeader = QString());

    // JSON-RPC dispatch. Returns true if a response was (or will be) sent.
    void dispatch(QTcpSocket *sock, const QJsonObject &req, const QString &sessionId);

    QString toolResultText(bool ok, const QString &value, const QString &message) const;

    WindowManager *m_windows = nullptr;
    QTcpServer *m_server = nullptr;
    int m_boundPort = 0;

    // Per-connection read buffer (HTTP requests can arrive fragmented).
    QHash<QTcpSocket *, QByteArray> m_buffers;

    // sessionId -> agent instance (the read-only window it drives).
    QHash<QString, CalcInstance *> m_sessions;

    // Async tool calls awaiting an engine result, keyed by a global eval id.
    struct Pending {
        QPointer<QTcpSocket> sock;
        QJsonValue rpcId;
    };
    QHash<quint64, Pending> m_pending;
    quint64 m_nextEvalId = 1;
};
