// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later

// WindowSpawner — creates calculator windows. A QML singleton so both the
// startup bootstrap (Main) and any open window can open another. QML owns the
// CalcWindow component; the C++ WindowManager owns the per-window CalcInstance.

pragma Singleton

import QtQuick
import io.github.mpengellyca.qalkulator

QtObject {
    id: spawner

    property Component _comp: Component { CalcWindow {} }

    // Open a window bound to an existing instance (used for the primary window).
    function open(instance) {
        var w = _comp.createObject(null, { inst: instance });
        if (w) {
            w.show();
        }
        return w;
    }

    // Open a brand-new temporary window with a fresh, accent-coloured instance.
    function openNew() {
        return open(WindowManager.createInstance());
    }
}
