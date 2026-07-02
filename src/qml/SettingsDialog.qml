// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// SettingsDialog — a simple, native settings surface (§11). Exposes result
// format, decimal places, thousands separator, angle unit, and persist-history
// count. Each change writes straight to Config and calls Config.save(); the
// backend re-emits livePreview so format/precision changes update instantly.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import io.github.mpengellyca.qalkulator

Kirigami.Dialog {
    id: root

    title: i18nc("@title:window", "Settings")
    preferredWidth: Kirigami.Units.gridUnit * 24
    standardButtons: Kirigami.Dialog.Close
    padding: Kirigami.Units.largeSpacing

    Kirigami.FormLayout {
        // Result format: normal / scientific / engineering -> Config.resultFormat.
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Result format:")
            model: [
                i18nc("@item result format", "Normal"),
                i18nc("@item result format", "Scientific"),
                i18nc("@item result format", "Engineering")
            ]
            currentIndex: Config.resultFormat
            onActivated: function (index) {
                Config.resultFormat = index;
                Config.save();
            }
        }

        // Decimal places: -1 == auto.
        RowLayout {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Decimal places:")
            spacing: Kirigami.Units.smallSpacing
            QQC2.CheckBox {
                id: autoDecimals
                text: i18nc("@option:check", "Auto")
                checked: Config.decimalPlaces < 0
                onToggled: {
                    Config.decimalPlaces = checked ? -1 : Math.max(0, decimalSpin.value);
                    Config.save();
                }
            }
            QQC2.SpinBox {
                id: decimalSpin
                enabled: !autoDecimals.checked
                from: 0
                to: 20
                value: Config.decimalPlaces < 0 ? 2 : Config.decimalPlaces
                onValueModified: {
                    Config.decimalPlaces = value;
                    Config.save();
                }
            }
        }

        // Thousands separator.
        QQC2.CheckBox {
            Kirigami.FormData.label: i18nc("@label:check", "Digit grouping:")
            text: i18nc("@option:check", "Thousands separator")
            checked: Config.thousandsSeparator
            onToggled: {
                Config.thousandsSeparator = checked;
                Config.save();
            }
        }

        // Angle unit: deg / rad / grad -> Config.angleUnit.
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Angle unit:")
            model: [
                i18nc("@item angle unit", "Degrees"),
                i18nc("@item angle unit", "Radians"),
                i18nc("@item angle unit", "Gradians")
            ]
            currentIndex: Config.angleUnit
            onActivated: function (index) {
                Config.angleUnit = index;
                Config.save();
            }
        }

        // Default currency: what "$", a bare currency amount, and an unspecified
        // conversion target resolve to. First entry follows the system locale;
        // the rest are currency codes -> Currency.setDefaultCurrency.
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Default currency:")
            model: [
                Currency.localeCurrency.length > 0
                    ? i18nc("@item:inlistbox default currency", "System default (%1)", Currency.localeCurrency)
                    : i18nc("@item:inlistbox default currency", "System default")
            ].concat(Currency.currencies)
            currentIndex: {
                const d = Currency.defaultCurrency;
                if (d.length === 0)
                    return 0;
                const i = Currency.currencies.indexOf(d);
                return i >= 0 ? i + 1 : 0;
            }
            onActivated: function (index) {
                Currency.setDefaultCurrency(index === 0 ? "" : Currency.currencies[index - 1]);
            }
            QQC2.ToolTip.text: i18nc("@info:tooltip", "What \"$\", a bare currency amount, and unspecified conversions resolve to.")
            QQC2.ToolTip.visible: hovered
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        // Persisted history count.
        QQC2.SpinBox {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Remember results:")
            from: 0
            to: 500
            value: Config.persistHistoryCount
            onValueModified: {
                Config.persistHistoryCount = value;
                Config.save();
            }
        }

        // KDE-exclusive: magnetic window linking via the companion KWin script.
        // Only shown on a KDE session where the script is installed.
        Kirigami.Separator {
            visible: Magnet.supported
            Kirigami.FormData.isSection: true
        }
        QQC2.CheckBox {
            visible: Magnet.supported
            Kirigami.FormData.label: i18nc("@label:check", "Window linking:")
            text: i18nc("@option:check", "Snap windows side by side (KDE)")
            checked: Magnet.enabled
            onToggled: Magnet.setEnabled(checked)
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Place windows edge-to-edge to link them; move or resize the row as one.")
            QQC2.ToolTip.visible: hovered
        }

        // --- AI agents (MCP) -------------------------------------------------
        // A local, token-guarded MCP server lets an AI agent use the engine; each
        // agent session opens its own read-only window so you see every step.
        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: mcpToggle
            Kirigami.FormData.label: i18nc("@label:check", "AI agents (MCP):")
            text: i18nc("@option:check", "Let AI agents use the engine")
            checked: Mcp.enabled
            onToggled: Mcp.setEnabled(checked)
            QQC2.ToolTip.text: i18nc("@info:tooltip", "Runs a loopback-only server. Each connected agent opens a read-only window you can watch.")
            QQC2.ToolTip.visible: hovered
        }

        // Warn if enabled but the listener could not bind.
        QQC2.Label {
            visible: Mcp.enabled && !Mcp.running
            Kirigami.FormData.label: i18nc("@label", "Status:")
            text: i18nc("@info", "Could not start the MCP server.")
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        // Connection details (copy into the agent's MCP client configuration).
        RowLayout {
            visible: Mcp.running
            Kirigami.FormData.label: i18nc("@label:textbox", "Server URL:")
            spacing: Kirigami.Units.smallSpacing
            QQC2.TextField {
                id: urlField
                readOnly: true
                text: Mcp.url
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            }
            QQC2.ToolButton {
                icon.name: "edit-copy"
                onClicked: Mcp.copyText(Mcp.url)
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy")
                QQC2.ToolTip.visible: hovered
            }
        }

        RowLayout {
            visible: Mcp.running
            Kirigami.FormData.label: i18nc("@label:textbox", "Token:")
            spacing: Kirigami.Units.smallSpacing
            QQC2.TextField {
                readOnly: true
                text: Mcp.token
                echoMode: TextInput.Normal
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            }
            QQC2.ToolButton {
                icon.name: "edit-copy"
                onClicked: Mcp.copyText(Mcp.token)
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy")
                QQC2.ToolTip.visible: hovered
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                onClicked: Mcp.regenerateToken()
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Generate a new token (existing clients must update).")
                QQC2.ToolTip.visible: hovered
            }
        }

        RowLayout {
            visible: Mcp.running
            Kirigami.FormData.label: i18nc("@label:textbox", "stdio command:")
            spacing: Kirigami.Units.smallSpacing
            QQC2.TextField {
                readOnly: true
                text: Mcp.bridgeCommand
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            }
            QQC2.ToolButton {
                icon.name: "edit-copy"
                onClicked: Mcp.copyText(Mcp.bridgeCommand)
                QQC2.ToolTip.text: i18nc("@info:tooltip", "Copy")
                QQC2.ToolTip.visible: hovered
            }
        }

        QQC2.Label {
            visible: Mcp.running
            text: Mcp.sessionCount > 0
                  ? i18ncp("@info", "%1 agent connected", "%1 agents connected", Mcp.sessionCount)
                  : i18nc("@info", "Point your agent's MCP client at the URL (HTTP) or the stdio command above.")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
    }
}
