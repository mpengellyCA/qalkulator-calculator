// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// StatusBar — the slim, muted bottom strip (§8 rule 4, §9.4). Bottom-left holds
// a real toggle switch for the keypad (bound to Config.keypadVisible) with its
// ⌃K keycap beside it; the toggle STAYS VISIBLE even when the keypad is hidden,
// so collapsing is never a trap. The right side shows contextual key hints for
// the current focus/mode via a Main-supplied `hints` list.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.kalk

Item {
    id: root

    // Contextual hints for the current mode/focus. Each: { keycap, label }.
    // Main sets this per context.
    property var hints: []

    implicitHeight: Kirigami.Units.gridUnit * 1.8

    Kirigami.Separator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // --- Keypad toggle (bottom-left, always visible) -----------------
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Kirigami.Units.smallSpacing

            QQC2.Switch {
                id: keypadSwitch
                checked: Config.keypadVisible
                onToggled: {
                    Config.keypadVisible = checked;
                    Config.save();
                }
                // Keep in sync if toggled elsewhere (Ctrl+K).
                Connections {
                    target: Config
                    function onKeypadVisibleChanged() {
                        keypadSwitch.checked = Config.keypadVisible;
                    }
                }
            }
            QQC2.Label {
                text: i18nc("@option:check keypad", "Keypad")
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
            KeyCap { text: "⌃K" }
        }

        Item { Layout.fillWidth: true }

        // --- Contextual key hints (right side) ---------------------------
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.hints
                delegate: RowLayout {
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    KeyCap { text: modelData.keycap; fontScale: 0.9 }
                    QQC2.Label {
                        text: modelData.label
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }
    }
}
