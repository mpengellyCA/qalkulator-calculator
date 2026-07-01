// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// AmountHistoryPopup — the converter's "recent results" dropdown. Unlike the
// Calculator's tape dropdown it lists only entries usable here: raw numbers and
// quantities in a unit compatible with the current From selection (computed in
// C++ by Engine.compatibleAmounts). Picking one loads its amount (already
// expressed in the From unit) into the converter.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

QQC2.Popup {
    id: root

    readonly property string monoFamily: Style.monoFamily

    // The filtered rows to show: [{expression, value, amount}, …] (newest first).
    property var entries: []

    // Emitted with the clean, re-parseable amount (already in the From unit).
    signal picked(string amount)

    // Anchored under its parent (the amount field); flips above it near the
    // window bottom (like the other dropdowns).
    property bool _flipUp: false
    readonly property real _estHeight: Kirigami.Units.gridUnit * 15
    x: 0
    width: parent ? parent.width : implicitWidth
    y: _flipUp ? -(implicitHeight + Kirigami.Units.smallSpacing)
               : ((parent ? parent.height : 0) + Kirigami.Units.smallSpacing)
    onAboutToShow: {
        const ov = QQC2.Overlay.overlay;
        root._flipUp = (ov && parent)
            ? (parent.mapToItem(ov, 0, parent.height).y + _estHeight > ov.height)
            : false;
    }

    modal: false
    focus: true
    padding: 0

    onOpened: {
        listView.currentIndex = root.entries.length > 0 ? 0 : -1;
        listView.forceActiveFocus();
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.25)
        radius: Kirigami.Units.smallSpacing
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 1
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.18)
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        QQC2.Label {
            visible: root.entries.length === 0
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            text: i18nc("@info empty dropdown", "No compatible results")
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.ScrollView {
            visible: root.entries.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(listView.contentHeight,
                                             Kirigami.Units.gridUnit * 12)
            clip: true

            ListView {
                id: listView
                model: root.entries
                keyNavigationEnabled: true
                highlightMoveDuration: 0

                highlight: Rectangle {
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                   Kirigami.Theme.highlightColor.g,
                                   Kirigami.Theme.highlightColor.b, 0.18)
                }

                delegate: QQC2.ItemDelegate {
                    id: entry
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    padding: Kirigami.Units.smallSpacing

                    onClicked: {
                        root.picked(entry.modelData.amount);
                        root.close();
                    }

                    background: Item {}

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: entry.modelData.expression
                            font.family: root.monoFamily
                            color: Kirigami.Theme.disabledTextColor
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            text: "= " + entry.modelData.value
                            font.family: root.monoFamily
                            font.bold: true
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (listView.currentIndex >= 0) {
                            root.picked(root.entries[listView.currentIndex].amount);
                        }
                        root.close();
                        event.accepted = true;
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            KeyCap { text: "↑↓"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info dropdown hint", "move")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            KeyCap { text: "⏎"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info dropdown hint", "use")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            Item { Layout.fillWidth: true }
            KeyCap { text: "esc"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info dropdown hint", "close")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }
}
