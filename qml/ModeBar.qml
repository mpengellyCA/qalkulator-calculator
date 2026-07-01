// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ModeBar — the quiet three-segment control that switches the whole screen
// between Calculator / Units / Currency (§6, §9.1). Equal-width segments, an
// accent underline + accent label on the active one, and each segment's ⌃1/⌃2/⌃3
// keycap. The access-key letter (C, U, r) is underlined only while Alt is held
// (progressive disclosure, §8 rule 3).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root

    property int currentIndex: 0
    property bool altHeld: false

    signal modeSelected(int index)

    implicitHeight: Kirigami.Units.gridUnit * 2.6

    readonly property var segments: [
        { text: i18nc("@title mode tab", "Calculator"), letter: "C", keycap: "⌃1" },
        { text: i18nc("@title mode tab", "Units"),      letter: "U", keycap: "⌃2" },
        { text: i18nc("@title mode tab", "Currency"),   letter: "r", keycap: "⌃3" }
    ]

    function labelMarkup(text, letter) {
        if (!root.altHeld)
            return text;
        var idx = text.indexOf(letter);
        if (idx < 0)
            return text;
        return text.substring(0, idx) + "<u>" + text.substring(idx, idx + 1) + "</u>" + text.substring(idx + 1);
    }

    // Subtle toolbar surface behind the whole bar.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.segments

            delegate: QQC2.AbstractButton {
                id: seg
                required property int index
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property bool current: root.currentIndex === index

                activeFocusOnTab: true
                Keys.onReturnPressed: root.modeSelected(index)
                Keys.onEnterPressed: root.modeSelected(index)

                onClicked: root.modeSelected(index)

                background: Rectangle {
                    color: seg.current
                           ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.10)
                           : (seg.hovered
                              ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                              : "transparent")
                    // Focus ring: a vibrant accent outline on the Tab-focused tab.
                    border.width: seg.activeFocus ? 2 : 0
                    border.color: Kirigami.Theme.highlightColor
                    Behavior on color { ColorAnimation { duration: 100 } }

                    // Active-segment accent bar along the bottom edge.
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 2
                        visible: seg.current
                        color: Kirigami.Theme.highlightColor
                    }
                }

                contentItem: Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: root.labelMarkup(seg.modelData.text, seg.modelData.letter)
                            textFormat: Text.StyledText
                            color: seg.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            font.bold: seg.current
                            verticalAlignment: Text.AlignVCenter
                        }
                        KeyCap {
                            text: seg.modelData.keycap
                            fontScale: 0.85
                            dim: !seg.current
                        }
                    }
                }
            }
        }
    }

    Kirigami.Separator {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    }
}
