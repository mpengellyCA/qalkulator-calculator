// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// AccessKeyOverlay — reveals true mnemonics while Alt is held (§8 rule 3).
// The mode tabs reveal their own underlines (ModeBar reads Main.altHeld); this
// lightweight layer renders small access-key badges near the actionable
// anchors — the three mode tabs (C / U / r) and the keypad toggle (K) — so the
// muscle-memory parity is visible without any permanent chrome. It is only
// visible while Alt is held; the actual Alt+C / Alt+U / Alt+R / Ctrl+K bindings
// live in Main.

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root

    // Driven by Main.altHeld.
    property bool active: false

    // Anchor rectangles (in this item's coordinates) that Main provides so the
    // badges sit over the right controls. Each: { x, y, letter }.
    property var anchorsList: []

    visible: active
    // Let clicks fall through to the controls beneath.
    enabled: false

    Repeater {
        model: root.anchorsList
        delegate: Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: badge.implicitWidth + Kirigami.Units.smallSpacing
            height: badge.implicitHeight + Kirigami.Units.smallSpacing * 0.5
            radius: Kirigami.Units.smallSpacing * 0.5
            color: Kirigami.Theme.highlightColor
            opacity: 0.92

            QQC2.Label {
                id: badge
                anchors.centerIn: parent
                text: modelData.letter
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
