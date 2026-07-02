// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ToolsBar — a slim actions strip between the ModeBar tabs and the content.
// Settings (gear) sits on the far left; the rest are context actions for the
// current mode. Calculator: clear history · paste value · paste expression ·
// copy expression. Units/Currency: favourites ▾ · paste value · copy result ·
// copy value. The bar only emits high-level intents — Main wires them to the
// expression field / active converter / register (§ single coordinator).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Item {
    id: root

    // 0 Calculator, 1 Units, 2 Currency.
    property int mode: 0
    // Current converter selections (Main binds these to the active converter),
    // used to label and save/remove the favourite for the current pair.
    property string curFrom: ""
    property string curTo: ""

    // Intents (Main performs them against the field / converter / register).
    signal settingsRequested()
    signal clearHistoryRequested()
    signal pasteValueRequested()        // calculator: insert clipboard as a value
    signal pasteExpressionRequested()   // calculator: replace the line with clipboard
    signal copyExpressionRequested()    // calculator: copy the expression text
    signal pasteAmountRequested()       // converter: paste clipboard into the amount
    signal copyResultRequested()        // converter: copy the converted output
    signal copyValueRequested()         // converter: copy the entered amount
    signal applyFavorite(string from, string to)
    signal newWindowRequested()         // open another temporary calculator window

    readonly property bool isCurrency: mode === 2
    readonly property bool isConverter: mode === 1 || mode === 2

    // Slim by design (~16 pt): small icons in a thin band.
    implicitHeight: Kirigami.Units.iconSizes.small + Math.round(Kirigami.Units.smallSpacing * 1.5)

    // --- Favourites helpers (persisted per converter type in Config) ------
    function _rawFavs() {
        return (root.isCurrency ? Config.favoriteCurrencyPairs
                                : Config.favoriteUnitPairs) || [];
    }
    function _favPairs() {
        var raw = root._rawFavs();
        var out = [];
        for (var i = 0; i < raw.length; ++i) {
            var p = String(raw[i]).split("|");
            if (p.length === 2 && p[0].length > 0 && p[1].length > 0)
                out.push({ from: p[0], to: p[1] });
        }
        return out;
    }
    function _isFavorited() {
        if (root.curFrom.length === 0 || root.curTo.length === 0)
            return false;
        return root._rawFavs().indexOf(root.curFrom + "|" + root.curTo) >= 0;
    }
    function _toggleFavorite() {
        if (root.curFrom.length === 0 || root.curTo.length === 0)
            return;
        var key = root.curFrom + "|" + root.curTo;
        var list = root._rawFavs().slice();
        var i = list.indexOf(key);
        if (i >= 0)
            list.splice(i, 1);
        else
            list.push(key);
        if (root.isCurrency)
            Config.favoriteCurrencyPairs = list;
        else
            Config.favoriteUnitPairs = list;
        Config.save();
    }
    // Friendly label for a stored unit/currency value (currencies are codes).
    function _label(value) {
        if (root.isCurrency)
            return value;
        var cats = Units.categories;
        for (var i = 0; i < cats.length; ++i)
            for (var j = 0; j < cats[i].units.length; ++j)
                if (cats[i].units[j].value === value)
                    return cats[i].units[j].label;
        return value;
    }

    // Subtle band + hairline under it, so it reads as a toolbar.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.04)
    }
    Kirigami.Separator {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0

        // Settings — far left, always present.
        SlimBtn {
            // KDE's standard "Settings/Configure" glyph (modern Breeze has no
            // plain cog in its action set; this is what every KDE app uses).
            icon.name: "settings-configure"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Settings (⌃,)")
            onClicked: root.settingsRequested()
        }

        Kirigami.Separator {
            Layout.preferredHeight: Math.round(root.height * 0.55)
            Layout.leftMargin: Kirigami.Units.smallSpacing / 2
            Layout.rightMargin: Kirigami.Units.smallSpacing / 2
            Layout.alignment: Qt.AlignVCenter
        }

        // --- Calculator context ------------------------------------------
        SlimBtn {
            visible: root.mode === 0
            icon.name: "edit-clear-history"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Clear history")
            onClicked: root.clearHistoryRequested()
        }
        SlimBtn {
            visible: root.mode === 0
            icon.name: "edit-paste-in-place"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Paste value at the cursor")
            onClicked: root.pasteValueRequested()
        }
        SlimBtn {
            visible: root.mode === 0
            icon.name: "edit-paste"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Paste expression (replace the line)")
            onClicked: root.pasteExpressionRequested()
        }
        SlimBtn {
            visible: root.mode === 0
            icon.name: "edit-copy"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy expression")
            onClicked: root.copyExpressionRequested()
        }

        // --- Converter context (Units + Currency) ------------------------
        SlimBtn {
            id: favBtn
            visible: root.isConverter
            icon.name: root._isFavorited() ? "favorite" : "bookmarks"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Favourite conversions")
            onClicked: {
                favMenu.pairs = root._favPairs();
                favMenu.parent = favBtn;
                favMenu.x = 0;
                favMenu.y = favBtn.height + 2;
                favMenu.open();
            }
        }
        SlimBtn {
            visible: root.isConverter
            icon.name: "edit-paste-in-place"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Paste value into the amount")
            onClicked: root.pasteAmountRequested()
        }
        SlimBtn {
            visible: root.isConverter
            icon.name: "edit-copy"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy result")
            onClicked: root.copyResultRequested()
        }
        SlimBtn {
            visible: root.isConverter
            icon.name: "edit-duplicate"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy value (the amount)")
            onClicked: root.copyValueRequested()
        }

        // Push the context actions to the left; window actions sit on the right.
        Item { Layout.fillWidth: true }

        // New temporary window (its own thread + accent) — a global action.
        SlimBtn {
            icon.name: "window-new"
            QQC2.ToolTip.text: i18nc("@info:tooltip", "New window (⌃N)")
            onClicked: root.newWindowRequested()
        }
    }

    // Favourites dropdown: saved pairs (click to apply) + a save/remove toggle
    // for the current pair. Rebuilt from Config each time the button is clicked.
    QQC2.Menu {
        id: favMenu
        property var pairs: []

        Instantiator {
            model: favMenu.pairs
            delegate: QQC2.MenuItem {
                required property var modelData
                text: root._label(modelData.from) + "  →  " + root._label(modelData.to)
                icon.name: "bookmarks"
                onTriggered: root.applyFavorite(modelData.from, modelData.to)
            }
            onObjectAdded: (index, object) => favMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => favMenu.removeItem(object)
        }

        QQC2.MenuSeparator { visible: favMenu.pairs.length > 0 }

        QQC2.MenuItem {
            enabled: root.curFrom.length > 0 && root.curTo.length > 0
                     && root.curFrom !== root.curTo
            icon.name: root._isFavorited() ? "list-remove" : "list-add"
            text: root._isFavorited()
                  ? i18nc("@action:inmenu", "Remove %1 → %2 from favourites",
                          root._label(root.curFrom), root._label(root.curTo))
                  : i18nc("@action:inmenu", "Save %1 → %2 to favourites",
                          root._label(root.curFrom), root._label(root.curTo))
            onTriggered: root._toggleFavorite()
        }
    }

    // A compact, icon-only toolbar button sized for the slim band.
    component SlimBtn: QQC2.ToolButton {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: Math.round(root.height * 0.95)
        Layout.preferredWidth: Math.round(root.height * 1.15)
        display: QQC2.AbstractButton.IconOnly
        icon.width: Kirigami.Units.iconSizes.small
        icon.height: Kirigami.Units.iconSizes.small
        padding: 0
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: 400
    }
}
