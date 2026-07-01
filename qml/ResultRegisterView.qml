// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ResultRegisterView — the Calculator "tape" (§6.1, §9.1). A ListView over the
// Register model showing "expression = value" rows, newest at the bottom,
// auto-scrolling on append. Single-click recalls a value into the expression
// field; double-click reloads its expression for re-editing. Each row reveals a
// faint "send ⌃→" affordance on hover.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.kalk

Item {
    id: root

    readonly property string monoFamily: Style.monoFamily

    // Insert the row's value into the expression field.
    signal valueRecalled(string value)
    // Reload the row's expression for re-editing.
    signal expressionEdit(string expression)
    // Send the row's value into the active converter (Ctrl+→ flow).
    signal sendToConverter(int row, string value)

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: 0
        model: Register

        // Newest is the highest index; keep the newest pinned to the bottom.
        verticalLayoutDirection: ListView.TopToBottom
        boundsBehavior: Flickable.StopAtBounds

        // Auto-scroll to the newest entry as it lands.
        onCountChanged: Qt.callLater(list.positionViewAtEnd)
        Component.onCompleted: Qt.callLater(list.positionViewAtEnd)

        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

        // Empty-state hint.
        QQC2.Label {
            anchors.centerIn: parent
            visible: list.count === 0
            text: i18nc("@info placeholder empty tape", "Results will appear here")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }

        delegate: QQC2.ItemDelegate {
            id: rowDelegate
            width: ListView.view.width

            required property int index
            required property string expression
            required property string value

            hoverEnabled: true
            padding: Kirigami.Units.smallSpacing

            background: Rectangle {
                color: rowDelegate.hovered
                       ? Qt.rgba(Kirigami.Theme.textColor.r,
                                 Kirigami.Theme.textColor.g,
                                 Kirigami.Theme.textColor.b, 0.05)
                       : "transparent"
            }

            // Single click → recall value; double click → re-edit expression.
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: root.valueRecalled(rowDelegate.value)
                onDoubleTapped: root.expressionEdit(rowDelegate.expression)
            }

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    text: rowDelegate.expression
                    font.family: root.monoFamily
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                // Faint "send ⌃→" affordance, revealed on hover.
                MouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: sendRow.implicitWidth
                    implicitHeight: sendRow.implicitHeight
                    visible: rowDelegate.hovered
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendToConverter(rowDelegate.index, rowDelegate.value)
                    RowLayout {
                        id: sendRow
                        spacing: Kirigami.Units.smallSpacing
                        opacity: 0.7
                        QQC2.Label {
                            text: i18nc("@action send result to converter", "send")
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.disabledTextColor
                        }
                        KeyCap { text: "⌃→"; fontScale: 0.9 }
                    }
                }

                QQC2.Label {
                    text: "= " + rowDelegate.value
                    font.family: root.monoFamily
                    font.bold: true
                    color: Kirigami.Theme.highlightColor
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
