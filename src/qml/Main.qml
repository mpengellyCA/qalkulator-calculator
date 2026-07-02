// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Main — the single-page host (§4, §9). A minimal Kirigami.ApplicationWindow
// with NO global drawer/hamburger. Holds the mode state, hosts the ModeBar, the
// ToolsBar, the Calculator stack (tape → expression + preview → keypad) and the
// ConverterView (Units + Currency), the pinned StatusBar, the results popup and
// the settings dialog. All global shortcuts and the flow wiring (§5.2, §7) live
// here. (Alt+C/U/R still jump to a mode; there is no reveal overlay.)

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Kirigami.ApplicationWindow {
    id: appWindow

    title: i18nc("@title:window", "QalKulator")

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
    Component.onCompleted: focusExpression()

    // --- Global shortcuts (§7) -------------------------------------------
    Shortcut { sequences: ["Ctrl+1"]; onActivated: appWindow.mode = 0 }
    Shortcut { sequences: ["Ctrl+2"]; onActivated: appWindow.mode = 1 }
    Shortcut { sequences: ["Ctrl+3"]; onActivated: appWindow.mode = 2 }

    // Alt+letter mnemonics jump to a mode (§8 rule 3).
    Shortcut { sequences: ["Alt+C"]; onActivated: appWindow.mode = 0 }
    Shortcut { sequences: ["Alt+U"]; onActivated: appWindow.mode = 1 }
    Shortcut { sequences: ["Alt+R"]; onActivated: appWindow.mode = 2 }

    // Copy current result from any field.
    Shortcut {
        sequences: [StandardKey.Copy]
        onActivated: {
            if (appWindow.isConverter)
                Engine.copyToClipboard(appWindow.activeConverter().currentOutput());
            else
                Engine.copyToClipboard(Engine.livePreview.length > 0
                                       ? Engine.livePreview : Engine.ans);
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
        onActivated: appWindow.sendResultToConverter(
            -1, Engine.livePreview.length > 0 ? Engine.livePreview : "")
    }
    Shortcut {
        sequences: ["Ctrl+Left"]
        enabled: appWindow.isConverter
        onActivated: appWindow.sendConvertedToCalculator()
    }

    // --- Flow wiring (§5.2) ----------------------------------------------
    // Ctrl+→ : send a result into the last-used converter and switch mode.
    // row < 0 means "use the newest/last result".
    function sendResultToConverter(row, value) {
        if (appWindow.mode !== 0)
            return; // Only meaningful from the Calculator.
        var v = value;
        if (v === undefined || v === "") {
            if (Register.count === 0)
                return;
            var r = (row !== undefined && row >= 0) ? row : Register.count - 1;
            v = Register.valueAt(r);
        }
        // Map lastConverterMode: 1 currency -> app mode 2; 0 units -> app mode 1.
        appWindow.mode = (Config.lastConverterMode === 0) ? 1 : 2;
        var conv = appWindow.activeConverter();
        conv.inboundTag =
            i18nc("@info inbound source tag", "brought from Calculator · via ⌃→");
        Qt.callLater(function () {
            conv.loadAmount(v);
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
        padding: 0
        topPadding: 0
        leftPadding: 0
        rightPadding: 0
        bottomPadding: 0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // --- ModeBar --------------------------------------------------
            ModeBar {
                id: modeBar
                Layout.fillWidth: true
                currentIndex: appWindow.mode
                onModeSelected: function (index) { appWindow.mode = index; }
            }

            // --- Tools strip: settings + per-mode context actions ---------
            ToolsBar {
                id: toolsBar
                Layout.fillWidth: true
                mode: appWindow.mode
                // Bind to the active converter's current pair (reactive to mode).
                curFrom: appWindow.mode === 2 ? currencyView.fromSel : unitsView.fromSel
                curTo:   appWindow.mode === 2 ? currencyView.toSel   : unitsView.toSel

                onSettingsRequested: settingsDialog.open()

                // Calculator actions.
                onClearHistoryRequested: Register.clear()
                onPasteValueRequested: {
                    expressionField.forceFocus();
                    expressionField.insertValue(Engine.clipboardText());
                }
                onPasteExpressionRequested: expressionField.loadExpression(Engine.clipboardText())
                onCopyExpressionRequested: Engine.copyToClipboard(expressionField.text)

                // Converter actions (act on the active converter).
                onPasteAmountRequested: appWindow.activeConverter().loadAmount(Engine.clipboardText())
                onCopyResultRequested: Engine.copyToClipboard(appWindow.activeConverter().currentOutput())
                onCopyValueRequested: Engine.copyToClipboard(appWindow.activeConverter().currentAmount())
                onApplyFavorite: function (from, to) { appWindow.activeConverter().applyPair(from, to); }
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onValueRecalled: function (v) { expressionField.insertValue(v); }
                        onExpressionEdit: function (e) { expressionField.loadExpression(e); }
                        onSendToConverter: function (row, v) {
                            appWindow.sendResultToConverter(row, v);
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Expression + live preview.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        ExpressionField {
                            id: expressionField
                            Layout.fillWidth: true
                            onOpenDropdownRequested: appWindow.openResultsPopup()
                            onClearAllRequested: {
                                Register.clear();
                            }
                            onCopyRequested: Engine.copyToClipboard(
                                Engine.livePreview.length > 0 ? Engine.livePreview : Engine.ans)
                            // Flow the live result if one is showing, else the last committed one.
                            onFlowRequested: appWindow.sendResultToConverter(
                                -1, Engine.livePreview.length > 0 ? Engine.livePreview : "")
                        }
                        ResultPreview {
                            id: resultPreview
                            Layout.fillWidth: true
                            hasInput: expressionField.text.length > 0
                        }
                    }
                }

                // (1) Units converter — its own independent state.
                ConverterView {
                    id: unitsView
                    isCurrency: false
                    onToCalcRequested: appWindow.sendConvertedToCalculator()
                    onCopyRequested: Engine.copyToClipboard(unitsView.currentOutput())
                }

                // (2) Currency converter — its own independent state.
                ConverterView {
                    id: currencyView
                    isCurrency: true
                    onToCalcRequested: appWindow.sendConvertedToCalculator()
                    onCopyRequested: Engine.copyToClipboard(currencyView.currentOutput())
                }
            }

            // --- Shared keypad: drives the expression field in Calculator
            // mode and the converter's amount field otherwise (§6.2/§6.3:
            // "driven by the same number keypad").
            Keypad {
                id: keypad
                Layout.fillWidth: true
                visible: Config.keypadVisible
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
            StatusBar {
                id: statusBar
                Layout.fillWidth: true
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
            Engine.commit(t);
            expressionField.clearEntry();
        }
    }

    // --- Results popup ----------------------------------------------------
    function openResultsPopup() {
        resultsPopup.open();
    }

    ResultRegisterPopup {
        id: resultsPopup
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
