// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ResultRegisterPopup — the Ctrl+Down recent-results dropdown (§7.1, §9.3).
// A floating popover anchored under the ExpressionField, listing recent results
// as "expression = value" newest-first. ↑/↓ navigate, Enter inserts the
// highlighted value, Esc closes, Ctrl+→ sends the highlighted row to the
// converter. A footer strip prints its own keys. Reads as elevation via a
// border + subtle popover shadow only (§8).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

QQC2.Popup {
    id: root

    // Anchored under its parent (the expression field). Opens downward, but flips
    // above the field when it would be clipped by the window's bottom edge — so it
    // is never cut off however short the window (or wherever the keypad sits).
    property bool _flipUp: false
    // Worst-case popup height used only to DECIDE the flip (the ListView's real
    // contentHeight fills in async); the flipped y binds to the real implicitHeight.
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

    readonly property string monoFamily: Style.monoFamily

    // Insert the chosen entry's value into the expression field.
    signal valueChosen(string value)
    // Send the highlighted entry to the converter (Ctrl+→ flow).
    signal sendToConverter(int row, string value)

    modal: false
    focus: true
    padding: 0
    // Show newest first: with a BottomToTop view the newest (highest model
    // index) renders at the top; highlight it and give the list active focus so
    // the arrow keys actually navigate it.
    onOpened: {
        if (Register.count > 0) {
            listView.currentIndex = Register.count - 1;
            listView.positionViewAtEnd();
        }
        listView.forceActiveFocus();
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.25)
        radius: Kirigami.Units.smallSpacing
        // Elevation reads via the border above plus the small drop shadow below,
        // the only elevation in the app (§8).

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
            visible: Register.count === 0
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            text: i18nc("@info empty dropdown", "No recent results")
            color: Kirigami.Theme.disabledTextColor
        }

        ListView {
            id: listView
            visible: Register.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight,
                                             Kirigami.Units.gridUnit * 12)
            clip: true
            focus: true
            model: Register
            keyNavigationEnabled: true
            highlightMoveDuration: 0

            QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

            highlight: Rectangle {
                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                               Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.18)
            }

            delegate: QQC2.ItemDelegate {
                id: entry
                width: ListView.view.width
                required property int index
                required property string expression
                required property string value

                readonly property bool active: ListView.isCurrentItem
                highlighted: active
                padding: Kirigami.Units.smallSpacing

                onClicked: {
                    listView.currentIndex = index;
                    root.valueChosen(entry.value);
                    root.close();
                }

                background: Item {}

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: entry.expression
                        font.family: root.monoFamily
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideRight
                    }
                    // "send ⌃→" on the highlighted row.
                    KeyCap {
                        visible: entry.active
                        text: "⌃→"
                        fontScale: 0.9
                    }
                    QQC2.Label {
                        text: "= " + entry.value
                        font.family: root.monoFamily
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                    }
                }
            }

            // Note: the model is oldest→newest by index, but the user reads
            // the dropdown newest-first. We flip the view direction so the
            // newest sits at the top and ↑/↓ feel natural.
            verticalLayoutDirection: ListView.BottomToTop

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (listView.currentIndex >= 0) {
                        var v = Register.valueAt(listView.currentIndex);
                        root.valueChosen(v);
                    }
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right
                           && (event.modifiers & Qt.ControlModifier)) {
                    if (listView.currentIndex >= 0) {
                        root.sendToConverter(listView.currentIndex,
                                             Register.valueAt(listView.currentIndex));
                    }
                    root.close();
                    event.accepted = true;
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Footer key strip.
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
                text: i18nc("@info dropdown hint", "insert")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            KeyCap { text: "⌃→"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info dropdown hint", "send")
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
