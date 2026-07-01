// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// KeyCap — a small, faint keyboard-cap ("kbd") pill that renders a shortcut
// string such as "⌃→", "⌃S" or "⌃K". It reads as quiet design, not noise:
// hairline border, muted surface, small monospace glyphs. Used throughout the
// UI to carry the "tell me the key" honesty from the design language (§8 rule 2).

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Item {
    id: root

    // The shortcut string to render, e.g. "⌃→".
    property alias text: label.text
    // Slightly smaller text for dense contexts.
    property real fontScale: 1.0
    // Extra-muted rendering (e.g. on an inactive tab).
    property bool dim: false

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    Rectangle {
        id: frame
        anchors.centerIn: parent
        implicitWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: label.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.smallSpacing * 0.75

        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, root.dim ? 0.04 : 0.06)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, root.dim ? 0.12 : 0.20)

        QQC2.Label {
            id: label
            anchors.centerIn: parent
            font.family: root.monoFamily
            font.pointSize: Math.max(1, Kirigami.Theme.smallFont.pointSize * root.fontScale)
            opacity: root.dim ? 0.5 : 0.75
            color: Kirigami.Theme.textColor
            textFormat: Text.PlainText
        }
    }

    // Shared monospace family used for numbers & keycaps app-wide (§8).
    // "monospace" resolves to the platform's default fixed-pitch font.
    readonly property string monoFamily: Style.monoFamily
}
