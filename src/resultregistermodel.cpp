// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "resultregistermodel.h"

#include "kalkconfig.h"

namespace
{
// 0x1F ASCII unit-separator used to join the three fields of a history entry.
const QChar kFieldSep = QChar(u'\x1f');
}

ResultRegisterModel::ResultRegisterModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ResultRegisterModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_entries.size();
}

QVariant ResultRegisterModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size()) {
        return {};
    }
    const Entry &e = m_entries.at(index.row());
    switch (role) {
    case EntryIdRole:
        return e.entryId;
    case ExpressionRole:
        return e.expression;
    case ValueRole:
        return e.value;
    case ContextRole:
        return e.context;
    case TimestampRole:
        return e.timestamp;
    default:
        return {};
    }
}

QHash<int, QByteArray> ResultRegisterModel::roleNames() const
{
    return {
        {EntryIdRole, QByteArrayLiteral("entryId")},
        {ExpressionRole, QByteArrayLiteral("expression")},
        {ValueRole, QByteArrayLiteral("value")},
        {ContextRole, QByteArrayLiteral("context")},
        {TimestampRole, QByteArrayLiteral("timestamp")},
    };
}

int ResultRegisterModel::count() const
{
    return m_entries.size();
}

void ResultRegisterModel::append(const QString &expression, const QString &value, const QString &context)
{
    const int row = m_entries.size();
    beginInsertRows(QModelIndex(), row, row);
    m_entries.append(Entry{m_nextId++, expression, value, context, QDateTime::currentDateTime()});
    endInsertRows();
    Q_EMIT countChanged();
}

QString ResultRegisterModel::valueAt(int row) const
{
    if (row < 0 || row >= m_entries.size()) {
        return {};
    }
    return m_entries.at(row).value;
}

QString ResultRegisterModel::expressionAt(int row) const
{
    if (row < 0 || row >= m_entries.size()) {
        return {};
    }
    return m_entries.at(row).expression;
}

QVariantMap ResultRegisterModel::get(int row) const
{
    if (row < 0 || row >= m_entries.size()) {
        return {};
    }
    const Entry &e = m_entries.at(row);
    return QVariantMap{
        {QStringLiteral("entryId"), e.entryId},
        {QStringLiteral("expression"), e.expression},
        {QStringLiteral("value"), e.value},
        {QStringLiteral("context"), e.context},
        {QStringLiteral("timestamp"), e.timestamp},
    };
}

void ResultRegisterModel::clear()
{
    if (m_entries.isEmpty()) {
        return;
    }
    beginResetModel();
    m_entries.clear();
    endResetModel();
    Q_EMIT countChanged();
}

void ResultRegisterModel::remove(int row)
{
    if (row < 0 || row >= m_entries.size()) {
        return;
    }
    beginRemoveRows(QModelIndex(), row, row);
    m_entries.removeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
}

void ResultRegisterModel::restore()
{
    const QStringList serialized = KalkConfig::self()->history();
    int cap = KalkConfig::self()->persistHistoryCount();
    if (cap < 0) {
        cap = 0;
    }

    beginResetModel();
    m_entries.clear();
    m_nextId = 1;

    // Restore at most `cap` entries, preferring the most recent (tail of list).
    int start = 0;
    if (cap > 0 && serialized.size() > cap) {
        start = serialized.size() - cap;
    }
    for (int i = start; i < serialized.size(); ++i) {
        // Each item: expression\x1fvalue\x1fcontext (context may be empty/absent).
        const QStringList fields = serialized.at(i).split(kFieldSep);
        const QString expression = fields.value(0);
        const QString value = fields.value(1);
        const QString context = fields.value(2);
        // Skip completely empty rows defensively.
        if (expression.isEmpty() && value.isEmpty()) {
            continue;
        }
        m_entries.append(Entry{m_nextId++, expression, value, context, QDateTime::currentDateTime()});
    }
    endResetModel();
    Q_EMIT countChanged();
}

void ResultRegisterModel::persist()
{
    int cap = KalkConfig::self()->persistHistoryCount();
    if (cap < 0) {
        cap = 0;
    }

    QStringList serialized;
    // Serialize the last `cap` entries (the newest ones live at the tail).
    int start = 0;
    if (cap > 0 && m_entries.size() > cap) {
        start = m_entries.size() - cap;
    } else if (cap == 0) {
        start = m_entries.size(); // persist nothing
    }
    serialized.reserve(m_entries.size() - start);
    // Strip any literal separator from fields so the split round-trips exactly.
    // (U+001F never occurs in real expressions/results, but be robust to paste.)
    const auto clean = [](QString s) { return s.remove(kFieldSep); };
    for (int i = start; i < m_entries.size(); ++i) {
        const Entry &e = m_entries.at(i);
        serialized.append(clean(e.expression) + kFieldSep + clean(e.value) + kFieldSep + clean(e.context));
    }
    // main.cpp owns the actual KConfig::save() on quit.
    KalkConfig::self()->setHistory(serialized);
}
