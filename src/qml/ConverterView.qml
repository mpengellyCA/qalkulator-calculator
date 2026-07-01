// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ConverterView — Units (isCurrency=false) and Currency (isCurrency=true) modes
// (§6.2, §6.3). A large editable "from" amount + a type-to-filter selector, a
// read-only "to" output with its own selector, and a swap control between them
// (Ctrl+S). Drives Engine.updateConversion live, persists selections to Config,
// and shows an inbound source chip during flow (§5.2).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Item {
    id: root

    readonly property string monoFamily: Style.monoFamily

    property bool isCurrency: false
    property string inboundTag: ""

    // Session-sticky filter text, shared by the From and To pickers of this
    // converter (so filtering once narrows both dropdowns until you clear it).
    property string sharedFilter: ""

    // Ctrl+← — send the converted value back to the calculator (§5.2).
    signal toCalcRequested()
    // Ctrl+C with no selection — copy the converted output.
    signal copyRequested()

    // Distinct channel per instance so each consumes only its own conversion
    // result from the Engine (no shared output state between Units and Currency).
    readonly property int channel: isCurrency ? 1 : 0

    // Local, per-view conversion result — fed by Engine.conversionUpdated.
    property string convResult: ""
    property string convRate: ""
    property bool convError: false

    property string fromSel: isCurrency ? Config.fromCurrency : Config.fromUnit
    property string toSel:   isCurrency ? Config.toCurrency   : Config.toUnit

    // --- Public surface (wired by Main) ----------------------------------
    function loadAmount(value) {
        amountField.text = value;
        amountField.forceActiveFocus();
        amountField.selectAll();
        root._recompute();
    }
    function currentOutput() {
        return root.convResult;
    }
    function focusAmount() {
        amountField.forceActiveFocus();
    }

    // --- Unit catalogue (grouped by type) --------------------------------
    // Shared source of truth (also used by the Calculator's unit autocomplete).
    readonly property var unitCategories: Units.categories

    // Display label for a stored unit/currency value.
    function _labelFor(value) {
        if (isCurrency)
            return value;
        for (var i = 0; i < unitCategories.length; ++i)
            for (var j = 0; j < unitCategories[i].units.length; ++j)
                if (unitCategories[i].units[j].value === value)
                    return unitCategories[i].units[j].label;
        return value; // fallback (e.g. a legacy stored value)
    }

    // --- Selection sources: return {label, value, category} rows ----------
    function _allOptions(filter) {
        var f = (filter || "").toLowerCase();
        var out = [];
        if (isCurrency) {
            var codes = Currency.currencies;
            if (codes === undefined || codes === null || codes.length === 0)
                codes = Engine.currencyCodes();
            for (var c = 0; c < codes.length; ++c) {
                if (f.length === 0 || codes[c].toLowerCase().indexOf(f) >= 0)
                    out.push({ label: codes[c], value: codes[c], category: "" });
            }
            return out;
        }
        // Units (incl. alias matching, e.g. "ft"/"feet" -> foot).
        return Units.filtered(filter);
    }

    // The unit category (Length/Area/…) a stored value belongs to, or "".
    function _categoryOf(value) {
        for (var i = 0; i < unitCategories.length; ++i)
            for (var j = 0; j < unitCategories[i].units.length; ++j)
                if (unitCategories[i].units[j].value === value)
                    return unitCategories[i].name;
        return "";
    }
    // A sensible default unit in `categoryName`, preferring one != excludeValue
    // (so From and To don't collapse to the same unit).
    function _firstCompatible(categoryName, excludeValue) {
        for (var i = 0; i < unitCategories.length; ++i) {
            if (unitCategories[i].name !== categoryName)
                continue;
            var units = unitCategories[i].units;
            for (var j = 0; j < units.length; ++j)
                if (units[j].value !== excludeValue)
                    return units[j].value;
            if (units.length > 0)
                return units[0].value;
        }
        return excludeValue;
    }

    function _persistFrom(v) {
        root.fromSel = v;
        if (isCurrency) {
            Config.fromCurrency = v;
        } else {
            Config.fromUnit = v;
            // Keep To in the same category as the just-picked From (currencies are
            // all inter-convertible, so this only matters for units).
            var cat = _categoryOf(v);
            if (cat !== "" && _categoryOf(root.toSel) !== cat) {
                root.toSel = _firstCompatible(cat, v);
                Config.toUnit = root.toSel;
            }
        }
        Config.save();
        root._recompute();
    }
    function _persistTo(v) {
        root.toSel = v;
        if (isCurrency) {
            Config.toCurrency = v;
        } else {
            Config.toUnit = v;
            var cat = _categoryOf(v);
            if (cat !== "" && _categoryOf(root.fromSel) !== cat) {
                root.fromSel = _firstCompatible(cat, v);
                Config.fromUnit = root.fromSel;
            }
        }
        Config.save();
        root._recompute();
    }

    function _recompute() {
        Engine.updateConversion(amountField.text, root.fromSel, root.toSel, root.isCurrency, root.channel);
    }

    // Consume only this view's own conversion result.
    Connections {
        target: Engine
        function onConversionUpdated(channel, result, rate, error) {
            if (channel !== root.channel)
                return;
            root.convResult = result;
            root.convRate = rate;
            root.convError = error;
        }
    }

    // Re-run the conversion when result formatting changes so the output updates
    // live (the calculator preview is refreshed separately in C++).
    Connections {
        target: Config
        enabled: root.visible
        function onResultFormatChanged() { root._recompute(); }
        function onDecimalPlacesChanged() { root._recompute(); }
        function onThousandsSeparatorChanged() { root._recompute(); }
    }

    // Recompute when this converter becomes the visible one (switching tabs),
    // so its output reflects its own inputs rather than a stale value.
    onVisibleChanged: if (visible) root._recompute()

    function swap() {
        var a = root.fromSel;
        var b = root.toSel;
        root._persistFrom(b);
        root._persistTo(a);
    }

    function keepValue() {
        Engine.commit(amountField.text + " " + root.fromSel + " to " + root.toSel);
    }

    // --- Shared keypad input (routed here by Main when in a converter) ----
    function keypadInsert(token) {
        amountField.forceActiveFocus();
        if (amountField.selectionStart !== amountField.selectionEnd)
            amountField.remove(amountField.selectionStart, amountField.selectionEnd);
        amountField.insert(amountField.cursorPosition, token);
        root._recompute();
    }
    function keypadBackspace() {
        var t = amountField.text;
        if (t.length > 0) {
            amountField.remove(amountField.cursorPosition - 1, amountField.cursorPosition);
            root._recompute();
        }
    }
    function keypadEquals() {
        root.keepValue();
    }

    Component.onCompleted: {
        // Heal an incompatible pair restored from config (e.g. km² → °C).
        if (!isCurrency) {
            var cat = _categoryOf(root.fromSel);
            if (cat !== "" && _categoryOf(root.toSel) !== cat) {
                root.toSel = _firstCompatible(cat, root.fromSel);
                Config.toUnit = root.toSel;
                Config.save();
            }
        }
        root._recompute();
    }

    Shortcut {
        sequence: "Ctrl+S"
        enabled: root.visible
        onActivated: root.swap()
    }


    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 1.5
        spacing: Kirigami.Units.largeSpacing

        // --- Inbound source chip (§8 rule 5) -----------------------------
        Kirigami.Chip {
            visible: root.inboundTag.length > 0
            Layout.alignment: Qt.AlignLeft
            text: root.inboundTag
            checkable: false
            closable: true
            onRemoved: root.inboundTag = ""
        }

        // --- FROM card ---------------------------------------------------
        FieldCard {
            Layout.fillWidth: true
            label: i18nc("@label converter source", "From")

            QQC2.TextField {
                id: amountField
                Layout.fillWidth: true
                focus: true
                font.family: root.monoFamily
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.9
                horizontalAlignment: Text.AlignRight
                background: null
                leftPadding: 0
                placeholderText: "0"
                KeyNavigation.tab: fromSelector
                onTextEdited: root._recompute()
                // The amount field claims Ctrl+←/Ctrl+C via ShortcutOverride, so
                // the window Shortcuts never see them — intercept here.
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.keepValue();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.ControlModifier)) {
                        root.toCalcRequested();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                        if (amountField.selectedText.length === 0) {
                            root.copyRequested();
                            event.accepted = true;
                        }
                    }
                }
            }
            QQC2.ToolButton {
                visible: amountField.text.length > 0
                icon.name: "edit-clear"
                display: QQC2.AbstractButton.IconOnly
                onClicked: {
                    amountField.clear();
                    amountField.forceActiveFocus();
                    root._recompute();
                }
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Clear amount")
                QQC2.ToolTip.visible: hovered
            }
            ConverterSelector {
                id: fromSelector
                selection: root.fromSel
                optionsFn: root._allOptions
                isCurrency: root.isCurrency
                KeyNavigation.tab: swapButton
                onSelected: function (v) { root._persistFrom(v); }
            }
        }

        // --- SWAP control -------------------------------------------------
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            QQC2.RoundButton {
                id: swapButton
                icon.name: "exchange-positions-symbolic"
                flat: false
                activeFocusOnTab: true
                onClicked: root.swap()
                KeyNavigation.tab: toSelector
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Swap from / to")
                QQC2.ToolTip.visible: hovered
            }
            KeyCap { text: "⌃S"; fontScale: 0.9 }
        }

        // --- TO card -----------------------------------------------------
        FieldCard {
            Layout.fillWidth: true
            label: i18nc("@label converter destination", "To")
            accent: true

            QQC2.Label {
                Layout.fillWidth: true
                text: root.convError
                      ? i18nc("@info conversion failed", "—")
                      : (root.convResult.length > 0 ? root.convResult : "0")
                font.family: root.monoFamily
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.9
                font.bold: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                color: root.convError
                       ? Kirigami.Theme.disabledTextColor
                       : Kirigami.Theme.highlightColor
            }
            ConverterSelector {
                id: toSelector
                selection: root.toSel
                optionsFn: root._allOptions
                isCurrency: root.isCurrency
                KeyNavigation.tab: amountField
                onSelected: function (v) { root._persistTo(v); }
            }
        }

        // --- Rate / info line --------------------------------------------
        QQC2.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: i18nc("@info conversion rate", "1 %1 = %2", root._labelFor(root.fromSel), root.convRate)
            visible: root.convRate.length > 0 && !root.convError
            color: Kirigami.Theme.disabledTextColor
            font.family: root.monoFamily
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // --- Updated date + refresh: tucked below the To value, bottom-left,
        // small (9pt) and quiet.
        RowLayout {
            visible: root.isCurrency
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Currency.available ? "download" : "network-disconnect"
                implicitWidth: 12
                implicitHeight: 12
                color: Kirigami.Theme.disabledTextColor
            }
            QQC2.Label {
                text: Currency.available
                      ? Currency.lastUpdated
                      : i18nc("@info offline currency note", "offline — using cached rates")
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: 9
            }
            QQC2.BusyIndicator {
                running: Currency.refreshing
                visible: Currency.refreshing
                implicitWidth: 14
                implicitHeight: 14
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                icon.width: 14
                icon.height: 14
                display: QQC2.AbstractButton.IconOnly
                padding: Kirigami.Units.smallSpacing
                implicitWidth: 24
                implicitHeight: 24
                enabled: !Currency.refreshing
                onClicked: Currency.refresh()
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Refresh exchange rates")
                QQC2.ToolTip.visible: hovered
            }
            Item { Layout.fillWidth: true } // keep the row left-aligned
        }

        Item { Layout.fillHeight: true }
    }

    // A framed card holding a label plus a [big field][selector] row.
    component FieldCard: Rectangle {
        id: card
        property string label: ""
        property bool accent: false
        default property alias _content: contentRow.data

        implicitHeight: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.smallSpacing * 1.5
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
        border.width: 1
        border.color: card.accent
                      ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
                      : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: card.label
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
            RowLayout {
                id: contentRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
            }
        }
    }

    // A selector that opens a searchable, filterable popup list — this is the
    // "type-to-filter" picker (§6.2/§6.3). Unlike an editable ComboBox it never
    // confuses the current selection with the filter text, so the full list is
    // always reachable.
    component ConverterSelector: QQC2.AbstractButton {
        id: sel
        property string selection: ""
        property var optionsFn: function (f) { return []; }
        property bool isCurrency: false
        signal selected(string value)

        // Kept for source compatibility; the list is re-queried on each open.
        function refresh() {}
        function forceOpen() { popup.open() }

        Layout.preferredWidth: Kirigami.Units.gridUnit * 7
        implicitHeight: Kirigami.Units.gridUnit * 2.2
        hoverEnabled: true
        // Reachable and openable by keyboard (Tab to it, then ↓/Space/Enter).
        activeFocusOnTab: true
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Space
                || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                popup.open();
                event.accepted = true;
            }
        }

        background: Rectangle {
            radius: Kirigami.Units.smallSpacing
            color: sel.pressed || popup.visible
                   ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                   : (sel.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) : "transparent")
            border.width: sel.activeFocus ? 2 : 1
            // A clear focus ring in the accent colour when Tab-focused.
            border.color: sel.activeFocus
                          ? Kirigami.Theme.highlightColor
                          : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: root._labelFor(sel.selection)
                elide: Text.ElideRight
                font.family: root.monoFamily
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }
            Kirigami.Icon {
                source: "arrow-down"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                opacity: 0.6
            }
        }

        onClicked: popup.open()

        function _pick(v) {
            if (v === undefined || v === "")
                return;
            // Emit only — the parent updates root.fromSel/toSel, which flows back
            // through the `selection` binding. Assigning sel.selection here would
            // break that binding (stale display after swap / mode change).
            sel.selected(v);
            popup.close();
        }

        // Rebuild the popup list from optionsFn(filter). Rows are {label, value,
        // category}; ListView.section turns the category into header rows (units
        // only — currency has no category, so no headers).
        function _populate(filter) {
            unitModel.clear();
            var opts = sel.optionsFn(filter);
            for (var i = 0; i < opts.length; ++i)
                unitModel.append(opts[i]);
            listView.currentIndex = unitModel.count > 0 ? 0 : -1;
        }

        // Pick the highlighted row, falling back to the top match when the model
        // rebuild has cleared currentIndex.
        function _commitCurrent() {
            var idx = listView.currentIndex >= 0 ? listView.currentIndex
                                                 : (unitModel.count > 0 ? 0 : -1);
            if (idx >= 0 && idx < unitModel.count)
                sel._pick(unitModel.get(idx).value);
        }

        // Highlight and scroll to the currently-selected value (if present in the
        // filtered list); otherwise sit at the top.
        function _selectCurrent() {
            var idx = -1;
            for (var i = 0; i < unitModel.count; ++i) {
                if (unitModel.get(i).value === sel.selection) {
                    idx = i;
                    break;
                }
            }
            if (idx < 0)
                idx = unitModel.count > 0 ? 0 : -1;
            listView.currentIndex = idx;
            if (idx >= 0)
                Qt.callLater(function () { listView.positionViewAtIndex(idx, ListView.Center); });
        }

        ListModel { id: unitModel }

        QQC2.Popup {
            id: popup
            width: Math.max(sel.width, Kirigami.Units.gridUnit * 10)
            // Right-align to the selector so a wider popup never spills off-window.
            x: sel.width - width
            y: sel.height + 2
            padding: 0
            modal: false

            onOpened: {
                // Restore the session-sticky, shared filter, then scroll to the
                // currently-selected value.
                searchField.text = root.sharedFilter;
                sel._populate(searchField.text);
                sel._selectCurrent();
                searchField.forceActiveFocus();
                searchField.selectAll();
            }

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
                    // Leave room for the clear button so text never runs under it.
                    rightPadding: clearFilterBtn.width + Kirigami.Units.smallSpacing
                    placeholderText: sel.isCurrency
                                     ? i18nc("@info:placeholder", "Filter currencies…")
                                     : i18nc("@info:placeholder", "Filter units…")
                    onTextChanged: {
                        root.sharedFilter = text; // sticky + shared across both pickers
                        sel._populate(text);
                    }
                    Keys.onDownPressed: listView.incrementCurrentIndex()
                    Keys.onUpPressed: listView.decrementCurrentIndex()
                    // Filtering rebuilds the model, which can reset currentIndex to
                    // -1; fall back to the first (top) match so Enter always picks.
                    Keys.onReturnPressed: sel._commitCurrent()
                    Keys.onEnterPressed: sel._commitCurrent()

                    // Clear the sticky filter.
                    QQC2.ToolButton {
                        id: clearFilterBtn
                        visible: searchField.text.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: Kirigami.Units.smallSpacing / 2
                        icon.name: "edit-clear"
                        icon.width: 14
                        icon.height: 14
                        display: QQC2.AbstractButton.IconOnly
                        padding: Kirigami.Units.smallSpacing / 2
                        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        onClicked: {
                            searchField.clear(); // -> onTextChanged clears sharedFilter + repopulates
                            searchField.forceActiveFocus();
                        }
                        QQC2.ToolTip.text: i18nc("@info:tooltip", "Clear filter")
                        QQC2.ToolTip.visible: hovered
                    }
                }

                Kirigami.Separator { Layout.fillWidth: true }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(listView.contentHeight, Kirigami.Units.gridUnit * 13)
                    clip: true

                    ListView {
                        id: listView
                        model: unitModel
                        keyNavigationEnabled: true
                        highlightMoveDuration: 0
                        currentIndex: 0

                        // Category header rows (units only; blank for currency).
                        section.property: sel.isCurrency ? "" : "category"
                        section.delegate: Rectangle {
                            required property string section
                            width: ListView.view.width
                            implicitHeight: headerLabel.implicitHeight + Kirigami.Units.smallSpacing
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                            QQC2.Label {
                                id: headerLabel
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
                            text: opt.label
                            highlighted: ListView.isCurrentItem
                            font.family: root.monoFamily
                            onClicked: sel._pick(opt.value)
                        }
                    }
                }
            }
        }
    }
}
