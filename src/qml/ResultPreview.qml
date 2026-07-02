// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ResultPreview — the live "= result" beneath the expression (§9.1).
// Shows inst.engine.livePreview in the accent color, monospace. Dims when input is
// empty; on a parse/eval error shows a subtle muted hint rather than a hard
// error. Carries a small copy affordance (⌃C).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Item {
    id: root

    property var inst

    readonly property string monoFamily: Style.monoFamily

    // True when the expression field currently has content (drives dimming).
    property bool hasInput: false

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.smallSpacing

        // "= value" (or a muted hint on error).
        QQC2.Label {
            id: previewLabel
            Layout.fillWidth: true
            font.family: root.monoFamily
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.25
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft

            readonly property bool showError: root.hasInput && inst.engine.livePreviewError

            text: {
                if (!root.hasInput)
                    return "";
                if (previewLabel.showError)
                    return i18nc("@info muted preview hint on error", "…");
                if (inst.engine.livePreview.length === 0)
                    return "";
                return "= " + inst.engine.livePreview;
            }

            color: previewLabel.showError
                   ? Kirigami.Theme.disabledTextColor
                   : Kirigami.Theme.highlightColor

            opacity: root.hasInput && inst.engine.livePreview.length > 0 ? 1.0 : 0.35
        }

        // Copy affordance — visible only when there is a live value to copy.
        MouseArea {
            id: copyArea
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: copyRow.implicitWidth
            implicitHeight: copyRow.implicitHeight
            visible: root.hasInput && !inst.engine.livePreviewError
                     && inst.engine.livePreview.length > 0
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: inst.engine.copyToClipboard(inst.engine.livePreview)

            RowLayout {
                id: copyRow
                spacing: Kirigami.Units.smallSpacing
                opacity: copyArea.containsMouse ? 1.0 : 0.6
                QQC2.Label {
                    text: i18nc("@action:button copy result", "copy")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
                KeyCap { text: "⌃C"; fontScale: 0.9 }
            }
        }
    }
}
