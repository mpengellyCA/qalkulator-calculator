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

    // Retain references to every open window: createObject(null, …) yields a
    // JS-owned object with no parent, which QML's GC would otherwise reclaim —
    // destroying the window (it flashes up, then vanishes while the process keeps
    // running). Keeping it in this array anchors it until the window is closed.
    property var _windows: []

    // Open a window bound to an existing instance (used for the primary window).
    function open(instance) {
        var w = _comp.createObject(null, { inst: instance });
        if (w) {
            _windows.push(w);
            w.show();
        }
        return w;
    }

    // Open a brand-new temporary window with a fresh, accent-coloured instance.
    function openNew() {
        return open(WindowManager.createInstance());
    }

    // Drop a closed window's reference so it can be freed.
    function forget(w) {
        var i = _windows.indexOf(w);
        if (i >= 0) {
            _windows.splice(i, 1);
        }
    }
}
