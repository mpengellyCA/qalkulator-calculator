// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "windowmanager.h"

#include "calcinstance.h"

#include <QGuiApplication>
#include <QPalette>
#include <QRandomGenerator>

#include <cmath>

WindowManager::WindowManager(QObject *parent)
    : QObject(parent)
{
    // Random starting hue each run; windows then step by the golden angle so
    // their accents stay vivid and well-separated without any matching logic.
    m_baseHue = QRandomGenerator::global()->bounded(360.0);
}

QColor WindowManager::accentForIndex(int index) const
{
    // Golden-angle hue stepping (137.508°) from the per-run base. Index 0 is the
    // primary (it uses the OS accent, so this is only ever called for index >= 1).
    const double hue = std::fmod(m_baseHue + index * 137.508, 360.0);
    return QColor::fromHslF(hue / 360.0, 0.72, 0.55);
}

CalcInstance *WindowManager::instanceAt(int i) const
{
    return (i >= 0 && i < m_instances.size()) ? m_instances.at(i) : nullptr;
}

int WindowManager::orderOf(CalcInstance *inst) const
{
    return static_cast<int>(m_instances.indexOf(inst));
}

CalcInstance *WindowManager::createPrimary()
{
    auto *inst = new CalcInstance(m_nextId++, /*primary=*/true, this);
    // The primary window keeps the OS accent (its theme is NOT overridden), but we
    // still record that accent — the real KDE highlight from the palette — so the
    // cross-window results popover can tint the primary's history correctly.
    inst->setAccentColor(QGuiApplication::palette().color(QPalette::Highlight));
    m_instances.append(inst);
    Q_EMIT instancesChanged();
    return inst;
}

CalcInstance *WindowManager::createInstance()
{
    auto *inst = new CalcInstance(m_nextId++, /*primary=*/false, this);
    inst->setAccentColor(accentForIndex(static_cast<int>(m_instances.size())));
    m_instances.append(inst);
    Q_EMIT instancesChanged();
    return inst;
}

void WindowManager::removeInstance(CalcInstance *inst)
{
    if (!inst || inst->primary()) {
        return; // the primary is never dropped
    }
    if (m_instances.removeOne(inst)) {
        inst->deleteLater();
        Q_EMIT instancesChanged();
    }
}
