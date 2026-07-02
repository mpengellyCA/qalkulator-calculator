// SPDX-FileCopyrightText: 2026 Mike Pengelly <https://github.com/mpengellyCA>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// QalKulator Window Linking — a KWin (Plasma 6) script that gives QalKulator's
// multiple windows "magnetic" behaviour that a Wayland client cannot do itself:
// drop two windows edge-to-edge and they snap flush + link; drag the leftmost
// (anchor) and the whole row travels together; drag any other window off by its
// title bar to detach it; resize and the row shares one height. Horizontal only.
//
// Watch it work:  journalctl -b -f | grep -i "qalkulator-magnetic:"

const APPID = "qalkulator";   // matched (substring) against resourceClass/Name
const SNAP = 24;              // px gap within which a released edge snaps + links

function log(m) { console.info("qalkulator-magnetic: " + m); }

function isOurs(w) {
    if (!w || !w.normalWindow) return false;
    const rc = ("" + (w.resourceClass || "")).toLowerCase();
    const rn = ("" + (w.resourceName || "")).toLowerCase();
    return rc.indexOf(APPID) >= 0 || rn.indexOf(APPID) >= 0;
}

function ourWindows() {
    return workspace.windowList().filter(isOurs);
}

// --- geometry helpers (frameGeometry is a QRectF: x, y, width, height) --------
function geo(w) {
    const g = w.frameGeometry;
    return { x: g.x, y: g.y, width: g.width, height: g.height };
}
function setGeo(w, x, y, width, height) {
    w.frameGeometry = Qt.rect(Math.round(x), Math.round(y),
                              Math.round(width), Math.round(height));
}
function rightOf(g) { return g.x + g.width; }
function bottomOf(g) { return g.y + g.height; }
function vOverlap(a, b) { return Math.min(bottomOf(a), bottomOf(b)) - Math.max(a.y, b.y); }

// --- link groups: arrays of windows, kept left→right --------------------------
let groups = [];

function groupOf(w) {
    for (let i = 0; i < groups.length; ++i) {
        if (groups[i].indexOf(w) >= 0) return groups[i];
    }
    return null;
}
function sortGroup(g) { g.sort(function (a, b) { return geo(a).x - geo(b).x; }); }
function dropTrivial() {
    groups = groups.filter(function (g) { return g.length >= 2; });
}
function removeFromGroup(w) {
    const g = groupOf(w);
    if (!g) return;
    g.splice(g.indexOf(w), 1);
    dropTrivial();
}
function mergeLink(a, b) {
    const ga = groupOf(a);
    const gb = groupOf(b);
    if (ga && gb) {
        if (ga === gb) return;
        for (let i = 0; i < gb.length; ++i) if (ga.indexOf(gb[i]) < 0) ga.push(gb[i]);
        groups.splice(groups.indexOf(gb), 1);
    } else if (ga) {
        ga.push(b);
    } else if (gb) {
        gb.push(a);
    } else {
        groups.push([a, b]);
    }
    sortGroup(groupOf(a));
}

// Re-flush a group edge-to-edge from its leftmost, sharing the leader's top+height.
function reflow(g) {
    if (!g || g.length < 2) return;
    sortGroup(g);
    const base = geo(g[0]);
    let x = base.x;
    for (let i = 0; i < g.length; ++i) {
        const go = geo(g[i]);
        setGeo(g[i], x, base.y, go.width, base.height);
        x += go.width;
    }
}

// On release, snap w flush to the nearest of our windows it was dropped beside.
function trySnap(w) {
    const gw = geo(w);
    let best = null, bestDist = SNAP + 1, toLeft = false;
    const list = ourWindows();
    for (let i = 0; i < list.length; ++i) {
        const o = list[i];
        if (o === w) continue;
        const go = geo(o);
        if (vOverlap(gw, go) <= 4) continue;      // must share vertical extent
        let d = Math.abs(gw.x - rightOf(go));      // w's left ~ o's right
        if (d < bestDist) { best = o; bestDist = d; toLeft = false; }
        d = Math.abs(rightOf(gw) - go.x);          // w's right ~ o's left
        if (d < bestDist) { best = o; bestDist = d; toLeft = true; }
    }
    if (!best) return false;
    const gb = geo(best);
    const h = Math.max(gw.height, gb.height);       // small grows to large
    setGeo(best, gb.x, gb.y, gb.width, h);
    const nx = toLeft ? gb.x - gw.width : rightOf(gb);
    setGeo(w, nx, gb.y, gw.width, h);
    mergeLink(w, best);
    log("linked (group size " + groupOf(w).length + ")");
    return true;
}

// --- per-window drag tracking -------------------------------------------------
const tracked = new Set();

function track(w) {
    if (tracked.has(w)) return;
    tracked.add(w);

    let startGeo = null;
    let lastGeo = null;
    let leaderDrag = false;

    w.interactiveMoveResizeStarted.connect(function () {
        startGeo = geo(w);
        lastGeo = startGeo;
        leaderDrag = false;
        const g = groupOf(w);
        if (g) {
            sortGroup(g);
            if (g[0] === w) {
                leaderDrag = true;          // dragging the anchor moves the row
            } else {
                removeFromGroup(w);          // dragging a follower pulls it off
                log("detached");
            }
        }
    });

    // While the anchor is dragged, translate the rest of the row with it.
    w.frameGeometryChanged.connect(function () {
        if (!leaderDrag) { lastGeo = geo(w); return; }
        const g = groupOf(w);
        if (!g) return;
        const cur = geo(w);
        const dx = cur.x - lastGeo.x;
        const dy = cur.y - lastGeo.y;
        lastGeo = cur;
        if (dx === 0 && dy === 0) return;
        for (let i = 0; i < g.length; ++i) {
            if (g[i] === w) continue;
            const go = geo(g[i]);
            setGeo(g[i], go.x + dx, go.y + dy, go.width, go.height);
        }
    });

    w.interactiveMoveResizeFinished.connect(function () {
        const cur = geo(w);
        const resized = startGeo && (cur.width !== startGeo.width || cur.height !== startGeo.height);
        if (resized && groupOf(w)) {
            const g = groupOf(w);            // resize → the whole row adopts this height
            for (let i = 0; i < g.length; ++i) {
                if (g[i] === w) continue;
                const go = geo(g[i]);
                setGeo(g[i], go.x, cur.y, go.width, cur.height);
            }
            reflow(g);
        } else if (leaderDrag) {
            reflow(groupOf(w));              // keep the row flush after an anchor move
        } else {
            trySnap(w);                      // a free window may snap to a neighbour
        }
        startGeo = null;
        leaderDrag = false;
    });

    w.closed.connect(function () {
        removeFromGroup(w);
        tracked.delete(w);
    });
}

// --- wire up ------------------------------------------------------------------
const existing = ourWindows();
for (let i = 0; i < existing.length; ++i) track(existing[i]);
workspace.windowAdded.connect(function (w) { if (isOurs(w)) track(w); });
log("loaded (" + existing.length + " QalKulator window(s) present)");
