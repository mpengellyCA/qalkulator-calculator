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
import io.github.mpengellyca.kalk

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
    }
}
