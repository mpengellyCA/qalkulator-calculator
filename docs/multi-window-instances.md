# Multi-window: linked temporary calculator instances — design

Status: **implemented** on branch `dev` (all three in-scope phases landed &
verified; magnetic linking deferred). Author-driven design; built in phases.

## Goal
Let the user open multiple *temporary* calculator windows, each an independent
**thread** of results for a separate use case, that can still **share results**
with one another. Secondary windows carry a vivid random accent colour so they
are instantly distinguishable, and the Results popover can browse other windows'
histories.

## Scope

**In (now):**
- Multiple windows, each with its **own history thread + engine state**.
- A **random vivid accent** per secondary window, overriding the OS accent; the
  main window keeps the OS accent.
- **Cross-window Results popover:** in the `Ctrl+↓` dropdown, `←/→` browse other
  windows' histories (start on your own, in open order); the list is tinted with
  that window's accent. `↑/↓`/`Enter` still act on **your** window.
- **Ephemeral:** a secondary window's history vanishes when it closes; only the
  main window's history persists across restarts (as today).

**Out / deferred:**
- **Magnetic window linking** (place side-by-side; move/resize as a group; detach
  by title bar). Blocked on **Wayland** — clients cannot read or set their own
  absolute window geometry, and there is no general KWin escape hatch. Revisit
  later as an X11/Windows-only feature or an internal split-pane model.

## Constraints
- **Wayland** (default KDE session): no absolute window positioning/geometry for
  clients → magnetic linking deferred.
- **One global libqalculate `CALCULATOR`** → every `CalculatorEngine` must
  serialize on a **shared** mutex.

## Architecture

- **`CalcInstance`** (QObject, one per window): owns its own
  `ResultRegisterModel` (exposed as **`history`**) and `CalculatorEngine`
  (**`engine`**). Also: `accentColor`, `id`, `order`, `primary`.
- **`WindowManager`** (C++ QML singleton, new): ordered `QList<CalcInstance*>`;
  `count`, `instanceAt(i)`, `orderOf(inst)`, `createInstance()`,
  `removeInstance(inst)`; assigns accent colours; emits `instancesChanged`.
- **Stay global (correctly shared):** `Config` (settings), `Currency` (rates).
- **`Engine`/`Register` stop being global QML singletons.** Each window's QML
  root (`CalcWindow`) has `property CalcInstance inst`; components take an `inst`
  and use `inst.engine` / `inst.history`. (`register` is a C++ keyword, hence
  the QML-facing name **`history`**.)
- **`Main.qml` → thin bootstrap** that creates the primary `CalcWindow`
  (`inst[0]`) on startup and spawns secondaries via `Component.createObject`.
  **`CalcWindow.qml`** = today's `Main` window UI, parameterised by `inst`.
- **Shared calc mutex:** promote the per-engine `m_calcMutex` to a process-global
  `QRecursiveMutex` used by all engines and `CurrencyService`.

## Feature mechanics
1. **Temp window + accent** — `Ctrl+N` (and a Tools-bar button) →
   `WindowManager.createInstance()` → a new `CalcWindow` bound to it. Accent =
   random vivid HSL (high S/V, hue kept distinct from the OS accent and other
   open windows), applied via `Kirigami.Theme.inherit:false` +
   `Kirigami.Theme.highlightColor` on the window root so the whole window adopts
   it. Main window keeps the OS accent.
2. **Cross-window Results popover** — `←/→` switch which window's history is
   shown (queried from `WindowManager`, starting on your own, in open order,
   wrapping at the ends). The popover re-tints (header/border/highlight) to that
   window's accent. `↑/↓`/`Enter` insert into **your** field; `Ctrl+→` flows to
   **your** converter. Footer gains a `←/→ window` hint.
3. **Magnetic linking** — deferred (see Scope).

## Build phases (each an independently-testable `dev` commit)
1. **Foundation** *(pure refactor, no UX change):* `CalcInstance` +
   `WindowManager` + shared mutex; move `Engine`/`Register` onto `inst`;
   `Main`→`CalcWindow` bootstrap. App still opens one window and behaves exactly
   as before.
2. **Second window + accent:** `Ctrl+N`/Tools button opens an accent-coloured
   temp window with its own empty thread; close drops the thread.
3. **Cross-window popover:** `←/→` navigation + accent tinting + footer hint.

## Minor decisions (defaults)
- New window: `Ctrl+N` + a Tools-bar button; no hard cap (hues recycle).
- Secondary window placement: wherever the compositor puts it (can't position on
  Wayland).
- Closing the main window quits the app; closing a secondary drops its thread.
