// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Main — the application bootstrap (the QML root loaded by main.cpp). It is
// non-visual: on startup it opens the primary calculator window bound to the
// primary CalcInstance. Every actual window is a CalcWindow; secondary ones are
// spawned on demand via WindowSpawner.

import QtQuick
import io.github.mpengellyca.qalkulator

QtObject {
    id: boot
    Component.onCompleted: WindowSpawner.open(WindowManager.instanceAt(0))
}
