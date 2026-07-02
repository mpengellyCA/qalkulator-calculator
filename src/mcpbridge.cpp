// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// qalkulator-mcp — a tiny stdio<->HTTP bridge so MCP clients that only speak
// stdio can reach QalKulator's loopback MCP server. It reads newline-delimited
// JSON-RPC messages on stdin, forwards each to the running app over HTTP (adding
// the shared token and carrying the session id), and writes the JSON response
// back to stdout. Port and token come from the app's own config (qalkulatorrc),
// or the QALKULATOR_MCP_PORT / QALKULATOR_MCP_TOKEN environment overrides.
//
// It is fully synchronous (blocking sockets, no event loop): one short-lived
// connection per message keeps the relay trivial and robust.

#include <QByteArray>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QStandardPaths>
#include <QString>
#include <QTcpSocket>

#include <iostream>
#include <string>

namespace
{
struct HttpReply {
    int status = 0;
    QByteArray body;
    QString sessionId;
};

// One blocking request/response round-trip. Returns status 0 on transport error.
HttpReply httpPost(quint16 port, const QString &token, const QString &sessionId, const QByteArray &payload)
{
    HttpReply reply;
    QTcpSocket sock;
    sock.connectToHost(QStringLiteral("127.0.0.1"), port);
    if (!sock.waitForConnected(2000)) {
        return reply;
    }

    QByteArray req;
    req += "POST /mcp HTTP/1.1\r\n";
    req += "Host: 127.0.0.1:" + QByteArray::number(port) + "\r\n";
    req += "Authorization: Bearer " + token.toUtf8() + "\r\n";
    if (!sessionId.isEmpty()) {
        req += "Mcp-Session-Id: " + sessionId.toUtf8() + "\r\n";
    }
    req += "Content-Type: application/json\r\n";
    req += "Content-Length: " + QByteArray::number(payload.size()) + "\r\n";
    req += "Connection: close\r\n\r\n";
    req += payload;

    sock.write(req);
    if (!sock.waitForBytesWritten(2000)) {
        return reply;
    }

    // Read headers.
    QByteArray buf;
    while (buf.indexOf("\r\n\r\n") < 0) {
        if (!sock.waitForReadyRead(30000)) {
            break;
        }
        buf += sock.readAll();
    }
    const int headerEnd = buf.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
        return reply;
    }

    const QByteArray header = buf.left(headerEnd);
    const QList<QByteArray> lines = header.split('\n');
    if (!lines.isEmpty()) {
        const QList<QByteArray> status = lines.first().trimmed().split(' ');
        reply.status = status.value(1).toInt();
    }
    int contentLength = 0;
    for (const QByteArray &line : lines) {
        const int colon = line.indexOf(':');
        if (colon <= 0) {
            continue;
        }
        const QString key = QString::fromUtf8(line.left(colon)).trimmed().toLower();
        const QString val = QString::fromUtf8(line.mid(colon + 1)).trimmed();
        if (key == QLatin1String("content-length")) {
            contentLength = val.toInt();
        } else if (key == QLatin1String("mcp-session-id")) {
            reply.sessionId = val;
        }
    }

    QByteArray bodyBuf = buf.mid(headerEnd + 4);
    while (bodyBuf.size() < contentLength) {
        if (!sock.waitForReadyRead(30000)) {
            break;
        }
        bodyBuf += sock.readAll();
    }
    reply.body = bodyBuf.left(contentLength);
    return reply;
}

// Discover the listening port: the configured one, else scan the small fallback
// range the server uses when its preferred port is taken.
quint16 discoverPort(int desired, const QString &token)
{
    for (int p = desired; p <= desired + 9; ++p) {
        QTcpSocket probe;
        probe.connectToHost(QStringLiteral("127.0.0.1"), static_cast<quint16>(p));
        if (probe.waitForConnected(300)) {
            probe.disconnectFromHost();
            return static_cast<quint16>(p);
        }
    }
    Q_UNUSED(token)
    return static_cast<quint16>(desired);
}

void emitLine(const QByteArray &json)
{
    std::cout << json.toStdString() << "\n";
    std::cout.flush();
}
} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("qalkulator"));

    // Resolve port + token: env overrides first, then qalkulatorrc [MCP].
    int desiredPort = qEnvironmentVariableIntValue("QALKULATOR_MCP_PORT");
    QString token = qEnvironmentVariable("QALKULATOR_MCP_TOKEN");
    if (desiredPort == 0 || token.isEmpty()) {
        const QString rc = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("qalkulatorrc"));
        if (!rc.isEmpty()) {
            QSettings cfg(rc, QSettings::IniFormat);
            cfg.beginGroup(QStringLiteral("MCP"));
            if (desiredPort == 0) {
                desiredPort = cfg.value(QStringLiteral("mcpPort"), 47600).toInt();
            }
            if (token.isEmpty()) {
                token = cfg.value(QStringLiteral("mcpToken")).toString();
            }
            cfg.endGroup();
        }
    }
    if (desiredPort == 0) {
        desiredPort = 47600;
    }

    const quint16 port = discoverPort(desiredPort, token);
    QString sessionId = qEnvironmentVariable("QALKULATOR_MCP_SESSION");

    // Relay stdin -> HTTP -> stdout, one line (one JSON-RPC message) at a time.
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) {
            continue;
        }
        const QByteArray payload = QByteArray::fromStdString(line);

        // Peek at the id so we can synthesise an error if the server is down.
        const QJsonObject msg = QJsonDocument::fromJson(payload).object();
        const bool isRequest = msg.contains(QStringLiteral("id"));

        const HttpReply reply = httpPost(port, token, sessionId, payload);
        if (!reply.sessionId.isEmpty()) {
            sessionId = reply.sessionId; // adopt the session assigned by initialize
        }

        if (reply.status == 0 || reply.status >= 400) {
            if (isRequest) {
                const QString detail = reply.status == 0
                    ? QStringLiteral("Cannot reach QalKulator on 127.0.0.1:%1 (is it running with MCP enabled?)").arg(port)
                    : QStringLiteral("QalKulator MCP server returned HTTP %1 (check the token).").arg(reply.status);
                const QJsonObject err{
                    {QStringLiteral("jsonrpc"), QStringLiteral("2.0")},
                    {QStringLiteral("id"), msg.value(QStringLiteral("id"))},
                    {QStringLiteral("error"), QJsonObject{{QStringLiteral("code"), -32001}, {QStringLiteral("message"), detail}}},
                };
                emitLine(QJsonDocument(err).toJson(QJsonDocument::Compact));
            }
            continue;
        }

        if (!reply.body.isEmpty()) {
            emitLine(reply.body);
        }
    }
    return 0;
}
