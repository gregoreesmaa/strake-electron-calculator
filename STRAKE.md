# Running this app under Strake (issue gregoreesmaa/strake#84)

This fork is **pristine upstream**
[`Alexintosh/Electron-Calculator`](https://github.com/Alexintosh/Electron-Calculator)
plus this file — no app source was changed. It boots under
[Strake](https://github.com/gregoreesmaa/strake), the native Electron
alternative, via the drop-in `require('electron')` shim.

## Run it

```sh
# In a Strake checkout:
cargo run -rp strake-run -- --prove-ipc /path/to/strake-electron-calculator
```

Observed output (Strake `main` @ `e40cefb4`, macOS/arm64, headless):

```text
app: Calculator (main: main.js)
main: ok, no JS errors
windows: 1
  #0 365x675 entry=/path/to/strake-electron-calculator/index.html
    title: Calculator
    preload: (none)
ipc: round-trip reply "strake:pong" (pumped 1)
```

Exit status is 0 only when the boot, the main script, and the
IPC round-trip all succeed.

## What this proves

- `main.js` runs unmodified: `require('electron')` → `app`/`BrowserWindow`,
  `require('path')` + `require('url')`
  (`path.join(__dirname, ...)` + `url.format({ protocol: 'file:' })`),
  `process.platform` guard, `app.on('ready')` firing `createWindow()`,
  `new BrowserWindow({ width: 365, height: 675 })`,
  `win.setResizable(false)`, `win.loadURL(file://…index.html)`,
  `win.on('closed')`, `window-all-closed` → `app.quit()`, and the
  `activate` re-create handler registered.
- One 365x675 window is created; `index.html` first-paints through the DOM
  pipeline (`<title>Calculator</title>` observed). The app declares no
  `webPreferences.preload`, so there is no preload step.
- One IPC round-trip settles: a harness-registered probe `ipcMain.handle`
  is invoked from the booted window's renderer via `ipcRenderer.invoke`
  (`strake:pong`, pumped 1). The app itself ships no IPC flow, so both probe
  endpoints are harness-driven — the handler, transport, and promise
  settlement are the app's own booted processes.

## Known gaps (follow-ups in gregoreesmaa/strake)

- **Renderer calculator logic**: the button wiring lives in
  `js/calculate.js` (jQuery) inside the renderer. The headless proof
  first-paints the entry page but does not execute page scripts for
  preload-less apps, so key-press → display behavior is unverified
  headless — headed-paint follow-up.
- **Headed open**: the boot is headless by design. Handing window #0 to a
  real OS surface (`ShellWindow::attach` on a live winit loop,
  `cargo run -rp strake-run --features headed -- --prove-headed <app-dir>`)
  still needs a display + eyeballs. The exact winit attributes the handoff
  consumes are pinned by tests, so this is verification, not new wiring.
- **DevTools**: `openDevTools()` stays commented out, as upstream.
- **Packaging**: `electron .` / installers are the packager epic
  ([strake#14](https://github.com/gregoreesmaa/strake/issues/14));
  `strake-run` is the `npm start` equivalent only.
