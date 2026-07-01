// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// UnitPickerPopup — a browse-the-whole-unit-list picker for the Calculator input
// (opened with Ctrl+U). Tailored to single-use insertion: choosing a unit emits
// picked(value) so the expression field can drop it at the caret. Grouped by
// category with a live filter. (Distinct from the converter's from/to selector.)

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

QQC2.Popup {
    id: root

    // Anchored under its parent (the expression field); flips above it when it
    // would be clipped by the window's bottom edge.
    property bool _flipUp: false
    readonly property real _estHeight: Kirigami.Units.gridUnit * 16
    x: 0
    width: parent ? parent.width : implicitWidth
    y: _flipUp ? -(implicitHeight + 2) : ((parent ? parent.height : 0) + 2)
    onAboutToShow: {
        const ov = QQC2.Overlay.overlay;
        root._flipUp = (ov && parent)
            ? (parent.mapToItem(ov, 0, parent.height).y + _estHeight > ov.height)
            : false;
    }

    readonly property string monoFamily: Style.monoFamily

    // Emitted with the libqalculate-parseable unit value to insert.
    signal picked(string value)

    padding: 0
    modal: false
    focus: true

    onOpened: {
        searchField.text = "";
        _populate("");
        searchField.forceActiveFocus();
    }

    function _populate(filter) {
        pickModel.clear();
        var opts = Units.filtered(filter);
        for (var i = 0; i < opts.length; ++i)
            pickModel.append(opts[i]);
        pickList.currentIndex = pickModel.count > 0 ? 0 : -1;
    }

    function _commitCurrent() {
        var idx = pickList.currentIndex >= 0 ? pickList.currentIndex
                                             : (pickModel.count > 0 ? 0 : -1);
        if (idx >= 0 && idx < pickModel.count) {
            root.picked(pickModel.get(idx).value);
            root.close();
        }
    }

    ListModel { id: pickModel }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.smallSpacing
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
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

        QQC2.TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            placeholderText: i18nc("@info:placeholder", "Insert a unit…")
            onTextChanged: root._populate(text)
            Keys.onDownPressed: pickList.incrementCurrentIndex()
            Keys.onUpPressed: pickList.decrementCurrentIndex()
            Keys.onReturnPressed: root._commitCurrent()
            Keys.onEnterPressed: root._commitCurrent()
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(pickList.contentHeight, Kirigami.Units.gridUnit * 14)
            clip: true

            ListView {
                id: pickList
                model: pickModel
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                currentIndex: 0

                section.property: "category"
                section.delegate: Rectangle {
                    required property string section
                    width: ListView.view.width
                    implicitHeight: sectionLabel.implicitHeight + Kirigami.Units.smallSpacing
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                    QQC2.Label {
                        id: sectionLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        text: parent.section
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.bold: true
                        color: Kirigami.Theme.disabledTextColor
                    }
                }

                delegate: QQC2.ItemDelegate {
                    id: opt
                    required property int index
                    required property string label
                    required property string value
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        root.picked(opt.value);
                        root.close();
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: opt.label
                            font.family: root.monoFamily
                        }
                        // Show the parseable value when it differs from the label,
                        // so the user learns the exact form to type.
                        QQC2.Label {
                            visible: opt.value !== opt.label
                            text: opt.value
                            font.family: root.monoFamily
                            color: Kirigami.Theme.disabledTextColor
                        }
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
                text: i18nc("@info picker hint", "move")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            KeyCap { text: "⏎"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info picker hint", "insert")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
            Item { Layout.fillWidth: true }
            KeyCap { text: "esc"; fontScale: 0.85 }
            QQC2.Label {
                text: i18nc("@info picker hint", "close")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }
}
