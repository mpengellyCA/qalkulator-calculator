// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Keypad — the collapsible button grid (§9.4). A proper calculator number pad:
// the 7-8-9 / 4-5-6 / 1-2-3 / 0 block sits in classic position on the left, the
// arithmetic operators run down a column, and a wide accented "=" anchors the
// bottom. Flat, hairline-bordered keys with generous spacing; operators and "="
// carry the accent. Every key types into the ExpressionField (or triggers
// backspace / equals) — it mirrors the keyboard but never gatekeeps it.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Item {
    id: root

    readonly property string monoFamily: Style.monoFamily

    signal keyPressed(string token)
    signal backspacePressed()
    signal equalsPressed()

    implicitHeight: grid.implicitHeight + grid.anchors.margins * 2

    // 5 columns, row-major. kind: digit | op | back | equals. `span` widens a key.
    readonly property var keys: [
        { label: "7", token: "7", kind: "digit" },
        { label: "8", token: "8", kind: "digit" },
        { label: "9", token: "9", kind: "digit" },
        { label: "÷", token: "÷", kind: "op" },
        { label: "⌫", token: "", kind: "back" },

        { label: "4", token: "4", kind: "digit" },
        { label: "5", token: "5", kind: "digit" },
        { label: "6", token: "6", kind: "digit" },
        { label: "×", token: "×", kind: "op" },
        { label: "(", token: "(", kind: "op" },

        { label: "1", token: "1", kind: "digit" },
        { label: "2", token: "2", kind: "digit" },
        { label: "3", token: "3", kind: "digit" },
        { label: "−", token: "-", kind: "op" },
        { label: ")", token: ")", kind: "op" },

        { label: "0", token: "0", kind: "digit" },
        { label: ".", token: ".", kind: "digit" },
        { label: "%", token: "%", kind: "op" },
        { label: "+", token: "+", kind: "op" },
        { label: "√", token: "sqrt(", kind: "op" },

        { label: "=", token: "", kind: "equals", span: 5 }
    ]

    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        columns: 5
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: root.keys
            delegate: QQC2.AbstractButton {
                id: btn
                required property var modelData

                readonly property bool isAccent: modelData.kind === "op"
                readonly property bool isEquals: modelData.kind === "equals"

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.columnSpan: modelData.span ? modelData.span : 1
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4

                // Reachable and activatable by keyboard, with a clear focus ring.
                activeFocusOnTab: true
                Keys.onReturnPressed: btn.clicked()
                Keys.onEnterPressed: btn.clicked()

                onClicked: {
                    switch (modelData.kind) {
                    case "back":   root.backspacePressed(); break;
                    case "equals": root.equalsPressed(); break;
                    default:       root.keyPressed(modelData.token); break;
                    }
                }

                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing
                    readonly property color accent: Kirigami.Theme.highlightColor
                    readonly property color textc: Kirigami.Theme.textColor
                    color: btn.isEquals
                           ? Qt.rgba(accent.r, accent.g, accent.b,
                                     btn.pressed ? 0.9 : (btn.hovered ? 0.78 : 0.65))
                           : btn.isAccent
                             ? Qt.rgba(accent.r, accent.g, accent.b,
                                       btn.pressed ? 0.30 : (btn.hovered ? 0.18 : 0.09))
                             : Qt.rgba(textc.r, textc.g, textc.b,
                                       btn.pressed ? 0.16 : (btn.hovered ? 0.09 : 0.035))
                    // Focus ring: a vibrant accent outline on the Tab-focused key.
                    border.width: btn.activeFocus ? 2 : 1
                    border.color: btn.activeFocus
                                  ? (btn.isEquals ? Kirigami.Theme.highlightedTextColor
                                                  : Kirigami.Theme.highlightColor)
                                  : (btn.isAccent || btn.isEquals
                                     ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                                     : Qt.rgba(textc.r, textc.g, textc.b, 0.14))

                    Behavior on color { ColorAnimation { duration: 80 } }
                    Behavior on border.color { ColorAnimation { duration: 80 } }
                }

                contentItem: QQC2.Label {
                    text: btn.modelData.label
                    font.family: root.monoFamily
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.35
                    font.bold: btn.isEquals
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: btn.isEquals
                           ? Kirigami.Theme.highlightedTextColor
                           : (btn.isAccent ? Kirigami.Theme.highlightColor
                                           : Kirigami.Theme.textColor)
                }
            }
        }
    }
}
