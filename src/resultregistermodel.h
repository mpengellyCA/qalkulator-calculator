// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ResultRegisterModel — the shared, ordered register of past results.
// A QAbstractListModel of committed calculations that every mode reads from.
// Newest entries live at the highest index (chronological order).

#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QList>
#include <QString>
#include <QVariantMap>

class ResultRegisterModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        EntryIdRole = Qt::UserRole + 1,
        ExpressionRole,
        ValueRole,
        ContextRole,
        TimestampRole,
    };
    Q_ENUM(Roles)

    explicit ResultRegisterModel(QObject *parent = nullptr);

    // QAbstractListModel
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    // Mutation / query API (used by the engine and QML)
    Q_INVOKABLE void append(const QString &expression, const QString &value, const QString &context);
    Q_INVOKABLE QString valueAt(int row) const;
    Q_INVOKABLE QString expressionAt(int row) const;
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void clear();
    Q_INVOKABLE void remove(int row);

    // KConfig-backed persistence (called from main.cpp)
    void restore();
    void persist();

Q_SIGNALS:
    void countChanged();

private:
    struct Entry {
        quint64 entryId;
        QString expression;
        QString value;
        QString context;
        QDateTime timestamp;
    };

    QList<Entry> m_entries; // index 0 = oldest, back() = newest
    quint64 m_nextId = 1;
};
