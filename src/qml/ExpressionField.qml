// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// ExpressionField — the primary editable expression line (§9.1, §7).
// Large monospace input that drives the engine live, commits on Enter/=,
// walks expression history with Up/Down (readline-style), and coordinates
// the results dropdown per the §7.1 Down-key resolution rule.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

FocusScope {
    id: root

    readonly property string monoFamily: Style.monoFamily

    // --- Public surface (wired by Main / Popup) --------------------------
    // The engine-friendly text of the current line.
    property alias text: field.text

    // Emitted when the user asks to open the recent-results dropdown.
    signal openDropdownRequested()
    // Emitted after a successful/attempted commit (Enter/=).
    signal committed()
    // Emitted on a second Esc when the line is already empty (clear-all).
    signal clearAllRequested()
    // Ctrl+C with no text selection — copy the current result (Main decides what).
    signal copyRequested()
    // Ctrl+→ — send the current result into the active converter (§5.2).
    signal flowRequested()

    implicitHeight: field.implicitHeight
    implicitWidth: Kirigami.Units.gridUnit * 12

    // --- History navigation state (readline-style over Register) ----------
    // -1 means "not navigating"; otherwise it's the row currently recalled.
    property int _historyPos: -1
    // Snapshot of the in-progress line before history walking began.
    property string _historyStash: ""

    function _resetHistory() {
        root._historyPos = -1;
        root._historyStash = "";
    }

    // --- Display <-> engine text substitution -----------------------------
    // The user sees × ÷ but the engine accepts * / × ÷ alike. We keep the
    // display glyphs in the field and hand libqalculate the same text (it
    // understands the Unicode operators), only normalising the caret-safe
    // conveniences.
    function _toDisplay(s) {
        return s.replace(/\*/g, "×").replace(/\//g, "÷");
    }

    // --- Public functions -------------------------------------------------
    function forceFocus() {
        field.forceActiveFocus();
    }

    // Insert a literal token at the caret (used by keypad, dropdown, tape).
    function insertValue(tokenText) {
        root._resetHistory();
        field.insert(field.cursorPosition, tokenText);
        Engine.updateInput(field.text);
    }
    // Alias kept for the contract naming used elsewhere.
    function insertToken(tokenText) {
        insertValue(tokenText);
    }

    // Replace the whole line for re-editing (double-click a tape row).
    function loadExpression(expr) {
        root._resetHistory();
        field.text = root._toDisplay(expr);
        field.cursorPosition = field.text.length;
        field.forceActiveFocus();
        Engine.updateInput(field.text);
    }

    // Clear just the entry.
    function clearEntry() {
        root._resetHistory();
        acPopup.close();
        field.clear();
        Engine.updateInput("");
    }

    // Append a display-operator, phone-style continuation on an empty line.
    function _isOperator(ch) {
        return ch === "+" || ch === "-" || ch === "−"
            || ch === "*" || ch === "×"
            || ch === "/" || ch === "÷"
            || ch === "^" || ch === "%";
    }

    // --- Unit autocomplete -------------------------------------------------
    // The trailing letter-run immediately before the caret (a unit-ish token).
    function _currentUnitToken() {
        var before = field.text.substring(0, field.cursorPosition);
        var m = before.match(/[A-Za-z°µ]+$/);
        return m ? m[0] : "";
    }

    // Refresh the inline unit suggestions for the token under the caret.
    function _updateUnitSuggestions() {
        var tok = root._currentUnitToken();
        if (tok.length < 2) {
            acPopup.close();
            return;
        }
        var s = Units.suggest(tok, 8);
        // Nothing useful, or the token already exactly equals the only match.
        if (s.length === 0
                || (s.length === 1 && s[0].value.toLowerCase() === tok.toLowerCase())) {
            acPopup.close();
            return;
        }
        acModel.clear();
        for (var i = 0; i < s.length; ++i) {
            acModel.append(s[i]);
        }
        acList.currentIndex = 0;
        if (!acPopup.visible) {
            acPopup.open();
        }
    }

    // Replace the token under the caret with the chosen unit value (+ a space).
    function _acceptUnit(value) {
        var pos = field.cursorPosition;
        var before = field.text.substring(0, pos);
        var m = before.match(/[A-Za-z°µ]+$/);
        var start = m ? pos - m[0].length : pos;
        var ins = value + " ";
        field.text = field.text.substring(0, start) + ins + field.text.substring(pos);
        field.cursorPosition = start + ins.length;
        acPopup.close();
        root._resetHistory();
        Engine.updateInput(field.text);
    }

    // Ctrl+U — browse the whole unit list and insert one at the caret.
    function _openUnitPicker() {
        acPopup.close();
        unitPicker.open();
    }

    QQC2.TextField {
        id: field
        anchors.fill: parent

        focus: true
        font.family: root.monoFamily
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.9
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        placeholderText: i18nc("@info:placeholder expression input", "Type an expression…")
        rightPadding: recentHint.width + Kirigami.Units.largeSpacing * 2

        // Flat, hairline surface per §8.
        background: Rectangle {
            color: "transparent"
            Kirigami.Separator {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }

        // Implicit continuation: an operator typed into an empty line prepends
        // the ans token (phone-style, §5.2). Runs before the char is inserted.
        Keys.onPressed: function (event) {
            // --- Unit autocomplete: navigate/accept while the popover is open.
            // Tab/↑/↓/Esc are captured here; Enter still commits (falls through).
            if (acPopup.visible) {
                if (event.key === Qt.Key_Tab) {
                    if (acList.currentIndex >= 0)
                        root._acceptUnit(acModel.get(acList.currentIndex).value);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Down && !(event.modifiers & Qt.ControlModifier)) {
                    acList.incrementCurrentIndex();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up && !(event.modifiers & Qt.ControlModifier)) {
                    acList.decrementCurrentIndex();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    acPopup.close();
                    event.accepted = true;
                    return;
                }
                // Caret-moving keys dismiss the popover but still act normally.
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                        || event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    acPopup.close();
                }
            }

            // Ctrl+U → browse the whole unit list and insert one at the caret.
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                root._openUnitPicker();
                event.accepted = true;
                return;
            }

            // Enter / = commit.
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || (event.key === Qt.Key_Equal && !(event.modifiers & Qt.ShiftModifier))) {
                root._commit();
                event.accepted = true;
                return;
            }

            // Ctrl+C: the field only auto-copies a live selection; with no
            // selection, hand off so the calculator copies the result. (An
            // editable TextField claims Ctrl+C via ShortcutOverride, so the
            // window-level Shortcut never sees it — we must intercept here.)
            if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                if (field.selectedText.length === 0) {
                    root.copyRequested();
                    event.accepted = true;
                }
                return;
            }

            // Ctrl+→: flow the result to the converter. The field would otherwise
            // eat Ctrl+Right as a word-jump, so intercept it here.
            if (event.key === Qt.Key_Right && (event.modifiers & Qt.ControlModifier)) {
                root.flowRequested();
                event.accepted = true;
                return;
            }

            // Ctrl+Backspace → delete previous token/word.
            if (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier)) {
                root._deleteToken();
                event.accepted = true;
                return;
            }

            // Ctrl+Down → always open the dropdown.
            if (event.key === Qt.Key_Down && (event.modifiers & Qt.ControlModifier)) {
                root.openDropdownRequested();
                event.accepted = true;
                return;
            }

            // Up → walk history backward (older).
            if (event.key === Qt.Key_Up && !(event.modifiers & Qt.ControlModifier)) {
                root._historyPrev();
                event.accepted = true;
                return;
            }

            // Down → §7.1 resolution.
            if (event.key === Qt.Key_Down && !(event.modifiers & Qt.ControlModifier)) {
                if (root._historyPos >= 0) {
                    // History navigation in progress → walk forward (newer).
                    root._historyNext();
                } else if (field.cursorPosition === field.text.length) {
                    // Caret at end, not navigating → open the dropdown.
                    root.openDropdownRequested();
                } else {
                    // Otherwise let the caret move naturally (no-op accept).
                    return;
                }
                event.accepted = true;
                return;
            }

            // Esc: Main handles popup-close first; here we clear entry, then
            // signal clear-all on a second Esc (empty line).
            if (event.key === Qt.Key_Escape) {
                if (field.text.length > 0) {
                    root.clearEntry();
                } else {
                    root.clearAllRequested();
                }
                event.accepted = true;
                return;
            }

            // Phone-style ans continuation: operator into an empty line.
            if (field.text.length === 0 && event.text.length === 1
                    && root._isOperator(event.text)) {
                var op = root._toDisplay(event.text);
                field.text = Engine.ansToken() + " " + op + " ";
                field.cursorPosition = field.text.length;
                Engine.updateInput(field.text);
                event.accepted = true;
                return;
            }
        }

        // Live display substitution + engine feed. onTextEdited fires only on
        // user edits, so programmatic changes above don't recurse.
        onTextEdited: {
            var disp = root._toDisplay(field.text);
            if (disp !== field.text) {
                var pos = field.cursorPosition;
                field.text = disp;
                field.cursorPosition = pos;
            }
            root._resetHistory();
            Engine.updateInput(field.text);
            root._updateUnitSuggestions();
        }

        // Never leave the suggestion popover floating when focus leaves.
        onActiveFocusChanged: if (!field.activeFocus) acPopup.close()
    }

    // "recent ⌃↓" affordance pinned to the right edge (§9.1), with a clear (✕)
    // button that appears once there is something to clear.
    RowLayout {
        id: recentHint
        anchors.right: field.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: field.verticalCenter
        spacing: Kirigami.Units.largeSpacing

        QQC2.ToolButton {
            visible: field.text.length > 0
            icon.name: "edit-clear"
            display: QQC2.AbstractButton.IconOnly
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
            onClicked: {
                root.clearEntry();
                root.forceFocus();
            }
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Clear (Esc)")
            QQC2.ToolTip.visible: hovered
        }

        MouseArea {
            opacity: 0.7
            Layout.fillHeight: true
            implicitWidth: hintRow.implicitWidth
            implicitHeight: hintRow.implicitHeight
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openDropdownRequested()

            RowLayout {
                id: hintRow
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    text: i18nc("@action recent results affordance", "recent")
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                }
                KeyCap { text: "⌃↓"; fontScale: 0.9 }
            }
        }
    }

    // --- Inline unit autocomplete popover --------------------------------
    // Advisory: it never steals focus (typing continues); ⇥ inserts, ↑↓ move,
    // Esc dismisses, and Enter still commits (handled in the field's Keys).
    ListModel { id: acModel }

    QQC2.Popup {
        id: acPopup
        parent: field
        focus: false
        modal: false
        padding: 0
        closePolicy: QQC2.Popup.CloseOnPressOutside
        width: Kirigami.Units.gridUnit * 13
        // Flip above the caret line when the suggestion list would be clipped by
        // the window bottom (e.g. keypad closed → field sits near the bottom).
        property bool _flipUp: false
        readonly property real _estHeight: Kirigami.Units.gridUnit * 14
        x: Math.max(0, Math.min(field.cursorRectangle.x, field.width - width))
        y: _flipUp ? (field.cursorRectangle.y - implicitHeight - 2)
                   : (field.cursorRectangle.y + field.cursorRectangle.height + 2)
        onAboutToShow: {
            const ov = QQC2.Overlay.overlay;
            acPopup._flipUp = ov
                ? (field.mapToItem(ov, 0, field.cursorRectangle.y + field.cursorRectangle.height).y
                   + _estHeight > ov.height)
                : false;
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

            ListView {
                id: acList
                model: acModel
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 12)
                clip: true
                keyNavigationEnabled: false // driven by the field's key handler
                highlightMoveDuration: 0
                currentIndex: 0

                delegate: QQC2.ItemDelegate {
                    id: acItem
                    required property int index
                    required property string label
                    required property string value
                    required property string category
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        root._acceptUnit(acItem.value);
                        root.forceFocus();
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: acItem.label
                            font.family: root.monoFamily
                            font.bold: true
                        }
                        // The parseable form, when it differs (teaches the syntax).
                        QQC2.Label {
                            visible: acItem.value !== acItem.label
                            text: acItem.value
                            font.family: root.monoFamily
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.Label {
                            text: acItem.category
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                KeyCap { text: "⇥"; fontScale: 0.85 }
                QQC2.Label {
                    text: i18nc("@info autocomplete hint", "insert")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
                KeyCap { text: "↑↓"; fontScale: 0.85 }
                QQC2.Label {
                    text: i18nc("@info autocomplete hint", "move")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
                Item { Layout.fillWidth: true }
                KeyCap { text: "⌃U"; fontScale: 0.85 }
                QQC2.Label {
                    text: i18nc("@info autocomplete hint", "all units")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }
    }

    // --- Full unit picker (Ctrl+U) ---------------------------------------
    UnitPickerPopup {
        id: unitPicker
        parent: field
        onPicked: function (value) {
            root.insertValue(value + " ");
        }
        onClosed: root.forceFocus()
    }

    // --- Internal behaviors ----------------------------------------------
    function _commit() {
        var expr = field.text;
        if (expr.trim().length === 0)
            return;
        acPopup.close();
        Engine.commit(expr);
        // Ready for continuation — clear the line; the result lands in the tape.
        field.clear();
        root._resetHistory();
        Engine.updateInput("");
        root.committed();
    }

    function _deleteToken() {
        // Delete the previous whitespace/operator-delimited token.
        var pos = field.cursorPosition;
        var before = field.text.substring(0, pos);
        // Trim trailing spaces, then a run of the same class.
        var trimmed = before.replace(/\s+$/, "");
        var m = trimmed.match(/([0-9.,]+|[^\s0-9.,]+)$/);
        var cut = m ? trimmed.length - m[0].length : 0;
        field.text = field.text.substring(0, cut) + field.text.substring(pos);
        field.cursorPosition = cut;
        Engine.updateInput(field.text);
        root._updateUnitSuggestions();
    }

    function _historyPrev() {
        var n = Register.count;
        if (n === 0)
            return;
        if (root._historyPos < 0) {
            // Begin navigation: stash the current line, jump to newest.
            root._historyStash = field.text;
            root._historyPos = n - 1;
        } else if (root._historyPos > 0) {
            root._historyPos = root._historyPos - 1;
        } else {
            return; // already at oldest
        }
        field.text = root._toDisplay(Register.expressionAt(root._historyPos));
        field.cursorPosition = field.text.length;
        Engine.updateInput(field.text);
    }

    function _historyNext() {
        if (root._historyPos < 0)
            return;
        var n = Register.count;
        if (root._historyPos < n - 1) {
            root._historyPos = root._historyPos + 1;
            field.text = root._toDisplay(Register.expressionAt(root._historyPos));
        } else {
            // Past the newest → restore the stashed in-progress line.
            root._historyPos = -1;
            field.text = root._historyStash;
            root._historyStash = "";
        }
        field.cursorPosition = field.text.length;
        Engine.updateInput(field.text);
    }
}
