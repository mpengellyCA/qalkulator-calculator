// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ResultRegisterPopup — the Ctrl+Down recent-results dropdown (§7.1, §9.3).
// A floating popover anchored under the ExpressionField, listing recent results
// as "expression = value" newest-first. ↑/↓ navigate rows, ←/→ browse OTHER
// windows' histories (starting on your own, in open order), Enter inserts the
// highlighted value into THIS window, Esc closes, Ctrl+→ sends the highlighted
// row to THIS window's converter. The list is tinted with the shown window's
// accent so you always know whose thread you're browsing. A footer prints keys.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

QQC2.Popup {
    id: root

    // This window's own instance (where chosen values land).
    property var inst

    // Cross-window browse: which window's history is shown. Reset to this window
    // on open; ←/→ cycle through all windows in open order (wrapping).
    property int viewIndex: 0
    readonly property var viewInst: WindowManager.instanceAt(viewIndex) || inst
    readonly property bool viewingOwn: viewInst === inst
    // Accent of the shown window (primary records its OS accent, so always valid).
    readonly property color viewAccent: (viewInst && viewInst.accentColor.a > 0)
                                        ? viewInst.accentColor
                                        : Kirigami.Theme.highlightColor

    // Anchored under its parent (the expression field). Opens downward, but flips
    // above the field when it would be clipped by the window's bottom edge.
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

    readonly property string monoFamily: Style.monoFamily

    // Insert the chosen entry's value into THIS window's expression field.
    signal valueChosen(string value)
    // Send the highlighted entry to THIS window's converter (Ctrl+→ flow).
    signal sendToConverter(int row, string value)

    modal: false
    focus: true
    padding: 0

    onOpened: {
        root.viewIndex = Math.max(0, WindowManager.orderOf(inst));
        root._resetSelection();
        listView.forceActiveFocus();
    }

    function _resetSelection() {
        if (viewInst && viewInst.history.count > 0) {
            listView.currentIndex = viewInst.history.count - 1; // newest
            listView.positionViewAtEnd();
        } else {
            listView.currentIndex = -1;
        }
    }
    function _cycleWindow(delta) {
        var n = WindowManager.count;
        if (n <= 1)
            return;
        root.viewIndex = (root.viewIndex + delta + n) % n;
        root._resetSelection();
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        // Border picks up the shown window's accent so cross-window browsing reads.
        border.color: root.viewingOwn
                      ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                Kirigami.Theme.textColor.b, 0.25)
                      : Qt.rgba(root.viewAccent.r, root.viewAccent.g, root.viewAccent.b, 0.7)
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

        // Cross-window header: a swatch of the shown window's accent + its place
        // in the open order. Only shown when more than one window is open.
        RowLayout {
            visible: WindowManager.count > 1
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 0.7
                implicitHeight: implicitWidth
                radius: implicitWidth / 2
                color: root.viewAccent
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: root.viewingOwn
                      ? i18nc("@info cross-window results", "This window")
                      : i18nc("@info cross-window results", "Window %1 of %2",
                              root.viewIndex + 1, WindowManager.count)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
            }
            KeyCap { text: "←→"; fontScale: 0.85 }
        }
        Kirigami.Separator {
            visible: WindowManager.count > 1
            Layout.fillWidth: true
        }

        QQC2.Label {
            visible: root.viewInst && root.viewInst.history.count === 0
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            text: i18nc("@info empty dropdown", "No recent results")
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.ScrollView {
            visible: root.viewInst && root.viewInst.history.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(listView.contentHeight,
                                             Kirigami.Units.gridUnit * 12)
            clip: true

        ListView {
            id: listView
            focus: true
            model: root.viewInst ? root.viewInst.history : null
            keyNavigationEnabled: true
            highlightMoveDuration: 0

            highlight: Rectangle {
                color: Qt.rgba(root.viewAccent.r, root.viewAccent.g, root.viewAccent.b, 0.18)
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
                    KeyCap {
                        visible: entry.active
                        text: "⌃→"
                        fontScale: 0.9
                    }
                    QQC2.Label {
                        text: "= " + entry.value
                        font.family: root.monoFamily
                        font.bold: true
                        color: root.viewAccent
                    }
                }
            }

            // Model is oldest→newest by index; the user reads newest-first, so the
            // view is flipped (newest at top, ↑/↓ natural).
            verticalLayoutDirection: ListView.BottomToTop

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (listView.currentIndex >= 0 && root.viewInst) {
                        root.valueChosen(root.viewInst.history.valueAt(listView.currentIndex));
                    }
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right
                           && (event.modifiers & Qt.ControlModifier)) {
                    if (listView.currentIndex >= 0 && root.viewInst) {
                        // Value only (row is into the viewed history, not ours).
                        root.sendToConverter(-1, root.viewInst.history.valueAt(listView.currentIndex));
                    }
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root._cycleWindow(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root._cycleWindow(1);
                    event.accepted = true;
                }
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
            KeyCap { text: "←→"; fontScale: 0.85; visible: WindowManager.count > 1 }
            QQC2.Label {
                visible: WindowManager.count > 1
                text: i18nc("@info dropdown hint", "window")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            KeyCap { text: "⏎"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info dropdown hint", "insert")
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
