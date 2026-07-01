// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Style — app-wide visual constants shared across components (§8), so values
// like the monospace family live in exactly one place.

pragma Singleton

import QtQuick

QtObject {
    // Monospace family for numbers & keycaps ("monospace" resolves to the
    // platform's default fixed-pitch font).
    readonly property string monoFamily: "monospace"
}
