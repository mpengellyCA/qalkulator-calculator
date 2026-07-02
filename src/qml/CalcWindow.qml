// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Main — the single-page host (§4, §9). A minimal Kirigami.ApplicationWindow
// with NO global drawer/hamburger. Holds the mode state, hosts the ModeBar, the
// ToolsBar, the Calculator stack (tape → expression + preview → keypad) and the
// ConverterView (Units + Currency), the pinned StatusBar, the results popup and
// the settings dialog. All global shortcuts and the flow wiring (§5.2, §7) live
// here. (Modes switch with Ctrl+1/2/3 only — no Alt shortcuts.)

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Kirigami.ApplicationWindow {
    id: appWindow

    property var inst

    // An agent window is driven entirely over MCP: read-only to the user, who
    // watches the agent's calculations land in the tape.
    readonly property bool _agent: inst && inst.agent

    title: _agent && inst.agentName.length > 0
           ? i18nc("@title:window agent-controlled window", "%1 · QalKulator", inst.agentName)
           : i18nc("@title:window", "QalKulator")

    // Secondary windows override the OS accent with their assigned vivid colour so
    // each thread is instantly distinguishable; the primary follows the OS accent
    // (inherit:true, which makes Kirigami ignore the placeholder highlightColor).
    // Secondary windows override the OS accent; the primary keeps it.
    readonly property bool _accented: inst && !inst.primary

    // Closing a secondary window drops its ephemeral thread and frees the window;
    // closing the primary quits the app (even if secondaries are still open). An
    // agent window additionally ends its MCP session (a no-op if the server
    // already tore it down).
    onClosing: {
        if (inst && inst.agent) {
            Mcp.endSession(inst);
        }
        if (inst && !inst.primary) {
            WindowManager.removeInstance(inst);
            WindowSpawner.forget(appWindow);
            appWindow.destroy();
        } else {
            Qt.quit();
        }
    }

    minimumWidth: Kirigami.Units.gridUnit * 20   // ~360 px
    // Never shrink past the point where the current tab + keypad fit (so the
    // keypad can't overlap the converter). All content-based, so no scrollbar.
    minimumHeight: modeBar.implicitHeight
                 + toolsBar.implicitHeight
                 + centerStack.Layout.minimumHeight
                 + (keypad.visible ? keypad.implicitHeight : 0)
                 + statusBar.implicitHeight
    width: Kirigami.Units.gridUnit * 24
    height: Kirigami.Units.gridUnit * 34

    // No hamburger / global drawer (§4).
    globalDrawer: null
    contextDrawer: null
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    // 0 Calculator, 1 Units, 2 Currency.
    property int mode: 0

    readonly property bool isConverter: mode === 1 || mode === 2

    // The converter instance for the current mode (Units and Currency each keep
    // their own independent amount + selections — no state bleed between them).
    function activeConverter() {
        return mode === 2 ? currencyView : unitsView;
    }

    // Focus the expression field when in Calculator mode.
    function focusExpression() {
        if (mode === 0)
            Qt.callLater(expressionField.forceFocus);
    }
    onModeChanged: {
        // Remember the last-used converter so Ctrl+→ targets it (§5.2, §11).
        if (mode === 1 && Config.lastConverterMode !== 0) {
            Config.lastConverterMode = 0;
            Config.save();
        } else if (mode === 2 && Config.lastConverterMode !== 1) {
            Config.lastConverterMode = 1;
            Config.save();
        }
        if (mode === 0)
            focusExpression();
        else
            Qt.callLater(activeConverter().focusAmount);
    }
    // (The primary's accent for the cross-window popover is recorded in C++ from
    // the real KDE palette highlight — see WindowManager::createPrimary.)
    Component.onCompleted: focusExpression()

    // --- Global shortcuts (§7) -------------------------------------------
    // Mode switching — Ctrl+1/2/3 (shown on the tab keycaps).
    Shortcut { sequences: ["Ctrl+1"]; onActivated: appWindow.mode = 0 }
    Shortcut { sequences: ["Ctrl+2"]; onActivated: appWindow.mode = 1 }
    Shortcut { sequences: ["Ctrl+3"]; onActivated: appWindow.mode = 2 }

    // Open a new temporary calculator window (its own thread + accent colour).
    Shortcut { sequences: [StandardKey.New]; onActivated: WindowSpawner.openNew() }
    // Close this window (a secondary drops its thread; the primary quits).
    Shortcut { sequences: [StandardKey.Close]; onActivated: appWindow.close() }

    // Copy current result from any field.
    Shortcut {
        sequences: [StandardKey.Copy]
        onActivated: {
            if (appWindow.isConverter)
                inst.engine.copyToClipboard(appWindow.activeConverter().currentOutput());
            else
                inst.engine.copyToClipboard(inst.engine.livePreview.length > 0
                                       ? inst.engine.livePreview : inst.engine.ans);
        }
    }

    // Toggle the keypad.
    Shortcut {
        sequences: ["Ctrl+K"]
        onActivated: {
            Config.keypadVisible = !Config.keypadVisible;
            Config.save();
        }
    }

    // Open settings.
    Shortcut {
        sequences: ["Ctrl+,"]
        onActivated: settingsDialog.open()
    }

    // Flow: Ctrl+Right / Ctrl+Left.
    Shortcut {
        sequences: ["Ctrl+Right"]
        onActivated: appWindow.flowRight()
    }
    Shortcut {
        sequences: ["Ctrl+Left"]
        enabled: appWindow.isConverter
        onActivated: appWindow.sendConvertedToCalculator()
    }

    // --- Flow wiring (§5.2) ----------------------------------------------
    // Ctrl+→ sends the current result into whichever converter fits its unit
    // type: a currency amount → Currency, a physical quantity → Units (with the
    // From unit pre-set), a raw number → Units. A SECOND Ctrl+→ within 1s (while
    // in a converter) escalates the destination to Currency. `_flowAmount`/
    // `_flowLastMs` remember the last sent value so the second press can reuse it.
    property double _flowLastMs: 0
    property string _flowAmount: ""

    function flowRight() {
        var now = Date.now();
        // Second Ctrl+→ within 1s → move the same value over to Currency.
        if (appWindow.isConverter && appWindow._flowAmount.length > 0
            && (now - appWindow._flowLastMs) < 1000) {
            appWindow._flowLastMs = now;
            appWindow._routeToCurrency(appWindow._flowAmount, "");
            return;
        }
        if (appWindow.mode !== 0)
            return; // Ctrl+→ only initiates a flow from the Calculator.
        appWindow.sendResultToConverter(
            -1, inst.engine.livePreview.length > 0 ? inst.engine.livePreview : "");
    }

    // Route a result (livePreview, or a specific register row) into the converter
    // that matches its unit type. Also used by the results dropdown and the tape
    // row "send" affordance. row < 0 means "use the newest/last result".
    function sendResultToConverter(row, value) {
        if (appWindow.mode !== 0)
            return; // Only meaningful from the Calculator.
        var v = value;
        if (v === undefined || v === "") {
            if (inst.history.count === 0)
                return;
            var r = (row !== undefined && row >= 0) ? row : inst.history.count - 1;
            v = inst.history.valueAt(r);
        }

        var cls = inst.engine.classifyAmount(v);
        var amount = (cls.amount && cls.amount.length > 0) ? cls.amount : v;
        appWindow._flowAmount = amount;
        appWindow._flowLastMs = Date.now();

        if (cls.kind === "currency") {
            appWindow._routeToCurrency(amount, cls.unit);
        } else if (cls.kind === "unit") {
            appWindow._routeToUnits(amount, Units.resolve(cls.unit) || Units.resolve(cls.unitName));
        } else {
            appWindow._routeToUnits(amount, ""); // raw number → Units, keep From
        }
    }

    function _routeToUnits(amount, fromValue) {
        appWindow.mode = 1;
        unitsView.inboundTag =
            i18nc("@info inbound source tag", "brought from Calculator · via ⌃→");
        Qt.callLater(function () {
            if (fromValue && fromValue.length > 0) {
                unitsView._persistFrom(fromValue); // heals the To unit too
                // Avoid a degenerate From === To (e.g. sending miles when the
                // converter's To was already miles): pick a different To.
                if (unitsView.toSel === fromValue) {
                    var alt = Units.firstCompatible(Units.categoryOf(fromValue), fromValue);
                    if (alt && alt !== fromValue)
                        unitsView._persistTo(alt);
                }
            }
            unitsView.loadAmount(amount);
        });
    }
    function _routeToCurrency(amount, fromCode) {
        appWindow.mode = 2;
        currencyView.inboundTag =
            i18nc("@info inbound source tag", "brought from Calculator · via ⌃→");
        Qt.callLater(function () {
            if (fromCode && fromCode.length > 0)
                currencyView._persistFrom(fromCode);
            currencyView.loadAmount(amount);
        });
    }

    // Ctrl+← : send the converter's current output back into the Calculator.
    function sendConvertedToCalculator() {
        var out = appWindow.activeConverter().currentOutput();
        appWindow.mode = 0;
        Qt.callLater(function () {
            expressionField.forceFocus();
            expressionField.clearEntry();
            if (out && out.length > 0)
                expressionField.insertValue(out);
        });
    }

    // --- Status bar hints per context ------------------------------------
    function currentHints() {
        if (appWindow.mode === 0) {
            return [
                { keycap: "⌃↓", label: i18nc("@info status hint", "results") },
                { keycap: "⌃U", label: i18nc("@info status hint", "units") },
                { keycap: "⌃→", label: i18nc("@info status hint", "convert") },
                { keycap: "⌃C", label: i18nc("@info status hint", "copy") }
            ];
        }
        return [
            { keycap: "⌃↓", label: i18nc("@info status hint", "recent") },
            { keycap: "⌃S", label: i18nc("@info status hint", "swap") },
            { keycap: "⌃←", label: i18nc("@info status hint", "to calc") },
            { keycap: "⌃C", label: i18nc("@info status hint", "copy") }
        ];
    }

    pageStack.initialPage: Kirigami.Page {
        id: page

        // Per-window accent: ONLY secondary windows override the OS highlight, and
        // only via a gated Binding — assigning highlightColor at all on the primary
        // (even a placeholder) blanks its OS accent, so the primary is left fully
        // untouched. Set on the Page (an Item) so it propagates to all content.
        Kirigami.Theme.inherit: !appWindow._accented
        Binding {
            target: page.Kirigami.Theme
            property: "highlightColor"
            value: appWindow.inst ? appWindow.inst.accentColor : Qt.rgba(0, 0, 0, 0)
            when: appWindow._accented
        }

        padding: 0
        topPadding: 0
        leftPadding: 0
        rightPadding: 0
        bottomPadding: 0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // --- Agent banner: shown only in an MCP-controlled window ------
            Rectangle {
                id: agentBanner
                Layout.fillWidth: true
                visible: appWindow._agent
                color: Kirigami.Theme.highlightColor
                implicitHeight: agentRow.implicitHeight + Kirigami.Units.largeSpacing

                RowLayout {
                    id: agentRow
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: "🤖"
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.highlightedTextColor
                        text: appWindow.inst && appWindow.inst.agentName.length > 0
                              ? i18nc("@info agent window banner", "%1 is controlling this window", appWindow.inst.agentName)
                              : i18nc("@info agent window banner", "An AI agent is controlling this window")
                    }
                    QQC2.Label {
                        text: i18nc("@info agent window banner", "read-only")
                        opacity: 0.85
                        color: Kirigami.Theme.highlightedTextColor
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            // --- ModeBar --------------------------------------------------
            ModeBar {
                id: modeBar
                Layout.fillWidth: true
                visible: !appWindow._agent
                currentIndex: appWindow.mode
                onModeSelected: function (index) { appWindow.mode = index; }
            }

            // --- Tools strip: settings + per-mode context actions ---------
            ToolsBar {
                id: toolsBar
                Layout.fillWidth: true
                visible: !appWindow._agent
                mode: appWindow.mode
                // Bind to the active converter's current pair (reactive to mode).
                curFrom: appWindow.mode === 2 ? currencyView.fromSel : unitsView.fromSel
                curTo:   appWindow.mode === 2 ? currencyView.toSel   : unitsView.toSel

                onSettingsRequested: settingsDialog.open()

                // Calculator actions.
                onClearHistoryRequested: inst.history.clear()
                onPasteValueRequested: {
                    expressionField.forceFocus();
                    expressionField.insertValue(inst.engine.clipboardText());
                }
                onPasteExpressionRequested: expressionField.loadExpression(inst.engine.clipboardText())
                onCopyExpressionRequested: inst.engine.copyToClipboard(expressionField.text)

                // Converter actions (act on the active converter).
                onPasteAmountRequested: appWindow.activeConverter().loadAmount(inst.engine.clipboardText())
                onCopyResultRequested: inst.engine.copyToClipboard(appWindow.activeConverter().currentOutput())
                onCopyValueRequested: inst.engine.copyToClipboard(appWindow.activeConverter().currentAmount())
                onApplyFavorite: function (from, to) { appWindow.activeConverter().applyPair(from, to); }
                onNewWindowRequested: WindowSpawner.openNew()
            }

            // --- Center: Calculator stack OR ConverterView ----------------
            StackLayout {
                id: centerStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                // A fixed minimum shared by every tab = the tallest tab (a
                // converter). Keeps all tabs the same minimum height and drives
                // the window's minimum so nothing gets clipped or overlapped.
                Layout.minimumHeight: Math.max(unitsView.implicitHeight,
                                               currencyView.implicitHeight)
                currentIndex: appWindow.mode

                // (0) Calculator stack.
                ColumnLayout {
                    spacing: 0

                    // Tape expands to fill available height.
                    ResultRegisterView {
                        id: tape
                        inst: appWindow.inst
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // In an agent window the tape is a live read-only view of
                        // the agent's work; ignore recall/edit/flow affordances.
                        onValueRecalled: function (v) { if (!appWindow._agent) expressionField.insertValue(v); }
                        onExpressionEdit: function (e) { if (!appWindow._agent) expressionField.loadExpression(e); }
                        onSendToConverter: function (row, v) {
                            if (!appWindow._agent)
                                appWindow.sendResultToConverter(row, v);
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true; visible: !appWindow._agent }

                    // Expression + live preview (hidden in a read-only agent window).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        visible: !appWindow._agent

                        ExpressionField {
                            id: expressionField
                            inst: appWindow.inst
                            Layout.fillWidth: true
                            onOpenDropdownRequested: appWindow.openResultsPopup()
                            onClearAllRequested: {
                                inst.history.clear();
                            }
                            onCopyRequested: inst.engine.copyToClipboard(
                                inst.engine.livePreview.length > 0 ? inst.engine.livePreview : inst.engine.ans)
                            // Flow the live result (else the last committed one) to
                            // the converter that fits its unit type.
                            onFlowRequested: appWindow.flowRight()
                        }
                        ResultPreview {
                            id: resultPreview
                            inst: appWindow.inst
                            Layout.fillWidth: true
                            hasInput: expressionField.text.length > 0
                        }
                    }
                }

                // (1) Units converter — its own independent state.
                ConverterView {
                    id: unitsView
                    inst: appWindow.inst
                    isCurrency: false
                    onToCalcRequested: appWindow.sendConvertedToCalculator()
                    onCopyRequested: inst.engine.copyToClipboard(unitsView.currentOutput())
                    onFlowRequested: appWindow.flowRight() // 2nd Ctrl+→ → Currency
                }

                // (2) Currency converter — its own independent state.
                ConverterView {
                    id: currencyView
                    inst: appWindow.inst
                    isCurrency: true
                    onToCalcRequested: appWindow.sendConvertedToCalculator()
                    onCopyRequested: inst.engine.copyToClipboard(currencyView.currentOutput())
                    onFlowRequested: appWindow.flowRight()
                }
            }

            // --- Shared keypad: drives the expression field in Calculator
            // mode and the converter's amount field otherwise (§6.2/§6.3:
            // "driven by the same number keypad").
            Keypad {
                id: keypad
                Layout.fillWidth: true
                visible: Config.keypadVisible && !appWindow._agent
                onKeyPressed: function (t) {
                    if (appWindow.mode === 0)
                        expressionField.insertValue(t);
                    else
                        appWindow.activeConverter().keypadInsert(t);
                }
                onBackspacePressed: {
                    if (appWindow.mode === 0) {
                        expressionField.forceFocus();
                        appWindow.keypadBackspace();
                    } else {
                        appWindow.activeConverter().keypadBackspace();
                    }
                }
                onEqualsPressed: {
                    if (appWindow.mode === 0) {
                        expressionField.forceFocus();
                        appWindow.keypadEquals();
                    } else {
                        appWindow.activeConverter().keypadEquals();
                    }
                }
            }

            // --- StatusBar (pinned) --------------------------------------
            // Hidden in an agent window: its shortcut hints and keypad toggle
            // don't apply to a read-only, MCP-driven view.
            StatusBar {
                id: statusBar
                Layout.fillWidth: true
                visible: !appWindow._agent
                hints: appWindow.currentHints()
            }
        }
    }

    // --- Keypad ⌫ / = via the expression field ---------------------------
    function keypadBackspace() {
        var t = expressionField.text;
        if (t.length > 0) {
            expressionField.loadExpression(t.substring(0, t.length - 1));
        }
    }
    function keypadEquals() {
        // Reuse the field's commit path by injecting an Enter-equivalent: the
        // simplest robust route is to commit the current text directly.
        var t = expressionField.text;
        if (t.trim().length > 0) {
            inst.engine.commit(t);
            expressionField.clearEntry();
        }
    }

    // --- Results popup ----------------------------------------------------
    function openResultsPopup() {
        resultsPopup.open();
    }

    ResultRegisterPopup {
        id: resultsPopup
        inst: appWindow.inst
        // Anchored to the expression field; it positions itself under the field
        // and flips above it near the window bottom (see ResultRegisterPopup).
        parent: expressionField
        onValueChosen: function (v) {
            expressionField.insertValue(v);
            expressionField.forceFocus();
        }
        onSendToConverter: function (row, v) {
            appWindow.sendResultToConverter(row, v);
        }
        onClosed: appWindow.focusExpression()
    }

    // --- Settings dialog --------------------------------------------------
    SettingsDialog {
        id: settingsDialog
        parent: appWindow.contentItem
    }

    // --- Global Esc: close popup / dialog first, else let the field clear --
    // ExpressionField handles clear-entry then clear-all when it has focus and
    // no popup is open; here we only intercept to close open surfaces first.
    Shortcut {
        sequences: [StandardKey.Cancel] // Esc
        enabled: resultsPopup.opened || settingsDialog.opened
        onActivated: {
            if (settingsDialog.opened)
                settingsDialog.close();
            else if (resultsPopup.opened)
                resultsPopup.close();
        }
    }
}
