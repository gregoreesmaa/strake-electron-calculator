# strake COMPAT — Electron-Calculator (Alexintosh, fork)

Upstream: https://github.com/Alexintosh/Electron-Calculator
Demo branch: `strake-demo` (this branch). Run: `bash strake-demo/RUN.sh`
Strake reference: `packages/strake-electron-compat` (`App`, `WindowManager`,
`WebContents`, `TOP50` coverage freeze in `src/coverage.rs`).

App profile: single-window Material-Design calculator. `main.js` (62 lines) is
the entire main process; `renderer.js` is empty (0 bytes); UI logic is plain
jQuery/DOM in `index.html` + `js/`. No IPC, no dialogs, no menus, no tray.

## What runs (verified by `strake-demo/RUN.sh`, node stdlib only)

Headless lifecycle simulation with a stub `electron` module (pattern mirrors
the `strake-vibey-script` harness: evaluate script → drive lifecycle events →
assert, cf. `ScriptDocument::execute_scripts` + event-loop tests):

- `node --check main.js` — parses.
- `ready` → `createWindow()` → exactly one `BrowserWindow(365x675)` — PASS.
- `setResizable(false)` applied — PASS (stub-level; see gap 1 below).
- `loadURL(file://…/index.html)` — PASS.
- `closed` → `window-all-closed` → `app.quit()` (static check; runtime
  quit skipped on darwin per the app's own `process.platform` guard) — PASS.
- `activate` re-create handler registered — PASS (not exercised headless).

No `npm install`, no Electron binary download, no `node_modules` committed.

## API-by-API mapping (every Electron touch in `main.js`)

| # | Electron API (main.js) | Strake counterpart | Status |
|---|------------------------|--------------------|--------|
| 1 | `app.on('ready', …)` | `App::on(AppEventKind::Ready)` / `App::mark_ready` | SHIMMED — lifecycle state machine (`app.rs`) |
| 2 | `app.on('window-all-closed', …)` | `App::on(WindowAllClosed)` + `note_window_closed(0)` | SHIMMED (`app.rs`) |
| 3 | `app.on('activate', …)` | `App::on(Activate)` | SHIMMED (`app.rs`) |
| 4 | `app.quit()` | `App::quit` (emits `before-quit` → `will-quit`) | SHIMMED (`app.rs`) |
| 5 | `new BrowserWindow({width: 365, height: 675})` | `WindowManager::create(BrowserWindowOptions { width: 365, height: 675, .. })` | SHIMMED (`window.rs`) |
| 6 | `win.setResizable(false)` | **no counterpart** — `BrowserWindowOptions` has `frame`, `show`, min/max size, but no `resizable` flag; no `set_resizable` on `WindowManager` | GAP — needs small shim addition (window chrome flag) |
| 7 | `win.loadURL(file:…index.html)` | `WebContents::load_url` (incl. `file://` normalization) | SHIMMED (`window.rs`) |
| 8 | `win.on('closed', …)` | `WindowManager::close` → `App::note_window_closed` | SHIMMED (`window.rs` + `app.rs`) |
| 9 | `webContents.openDevTools` (commented out, line 28) | `Deferred: devtools UI` | DEFERRED — not exercised; stays commented |
| 10 | `process.platform !== 'darwin'` guard | Node runtime value, outside the shim | NATIVE (no mapping needed) |

Neither `ipcMain`/`ipcRenderer`, `dialog`, `Menu`/`Tray`, `clipboard`,
`shell`, `screen`, `globalShortcut`, nor `nativeTheme` appear anywhere in the
app (`grep` over `main.js`, `renderer.js`, `js/` confirms) — so all of the
TOP50 `Deferred` entries are correctly *unneeded* for this app rather than
blockers.

## Key gaps (honest, ordered by severity)

1. **`setResizable` has no shim target (minor, blocks pixel-fidelity).**
   `BrowserWindowOptions` (`window.rs`) models `frame`/`min_size`/`max_size`
   but not `resizable`, and `WindowManager` has no `set_resizable`. The app
   still boots and lays out without it (fixed-size 365×675 calculator becomes
   resizable), so this is a fidelity gap, not a boot blocker. Suggested
   strake-side fix: add `resizable: bool` (default `true`) to
   `BrowserWindowOptions` + `WindowManager::set_resizable`, mirroring the
   existing `set_always_on_top`/`set_title` mutators.
2. **Renderer JS (jQuery + calculator logic in `index.html`) needs the
   `strake-vibey-script` DOM layer, not the compat shim.** The compat crate
   covers the main process; button wiring runs in the renderer. jQuery's
   DOM/CSS/animation surface far exceeds the vibey-script conformance suite
   (`tests/dom.rs`, `event_loop.rs`, `preact.rs`), so renderer fidelity is
   unverified headless — expected follow-up, not a main-process gap.
3. **`openDevTools` deferred (non-issue).** Line 28 is commented out upstream;
   mapped to `Deferred: devtools UI` in TOP50. No action unless debugging the
   renderer on strake.

## Deferred-with-issue (TOP50 entries this app does NOT need)

For the record — none of these block this demo, listed so a reader can see
the full freeze was considered: `Menu.*` / `Tray.*` (needs #12 native
menus/tray), `dialog.*` (needs #12 native dialogs), `clipboard.*` (bind
strake-shell clipboard), `shell.*` (needs #12 OS integration),
`screen.getPrimaryDisplay` (winit monitor bridge), `globalShortcut` (OS
hotkeys), `nativeTheme.*` (needs #12 theme bridge), `webPreferences`
(needs #18 N-API preload sandbox), `executeJavaScript`/`printToPDF`
(renderer JS-engine binding / shell printing).

## Verdict

**Main process: bootable on strake's MVP shim today** modulo the trivial
`resizable` flag addition. The `COMPAT.md` gap analysis above plus the green
`RUN.sh` lifecycle trace IS the deliverable per contract (headless boot of
the real `main.js` logic verified at the stub level; full Rust
`App`/`WindowManager` binding is strake-side follow-up). No PRs opened
against upstream; all demo material lives on this fork branch under
`strake-demo/`.
