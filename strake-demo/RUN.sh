#!/usr/bin/env bash
# strake-demo: best-effort headless boot of this app's main.js
# against strake's Electron-compat surface (report only, no strake checkout mods).
#
# What it does (node stdlib only, no npm install, no Electron download):
#   1. `node --check main.js` syntax gate.
#   2. Headless lifecycle simulation with a stub `electron` module, mirroring
#      the strake-vibey-script harness pattern (ScriptDocument event loop:
#      evaluate main-process script -> drive lifecycle events -> assert):
#        ready -> createWindow -> loadURL(index.html) -> closed
#        -> window-all-closed -> app.quit() (non-darwin)
#      The stub records the same state strake-electron-compat models in Rust
#      (App::on/mark_ready/quit, WindowManager::create/close, WebContents::load_url).
#   3. Prints PASS/FAIL per lifecycle step + the API surface main.js touched.
#
# Full-fidelity boot (Boa ScriptDocument + App/WindowManager bindings) is a
# strake-side follow-up; this script is the headless smoke signal for COMPAT.md.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== strake-demo headless boot: Electron-Calculator main.js =="

echo "--- [1/2] node --check main.js"
node --check main.js
echo "PASS: main.js parses"

echo "--- [2/2] headless lifecycle simulation (stub electron)"
node -e '
const Module = require("module");
const path = require("path");
const assert = require("assert");
const fs = require("fs");
const os = require("os");

const events = [];
const windows = [];
let quitCalled = false;

const appHandlers = {};
const app = {
  on: (ev, cb) => { (appHandlers[ev] = appHandlers[ev] || []).push(cb); },
  quit: () => { quitCalled = true; events.push("app.quit"); },
};

class FakeWindow {
  constructor(opts) {
    this.opts = opts; this.resizable = true; this.url = null;
    this.handlers = {};
    windows.push(this);
    events.push(`BrowserWindow created ${opts.width}x${opts.height}`);
  }
  setResizable(v) { this.resizable = v; events.push(`setResizable(${v})`); }
  loadURL(u) { this.url = u; events.push(`loadURL(${u})`); }
  on(ev, cb) { (this.handlers[ev] = this.handlers[ev] || []).push(cb); }
  close() { (this.handlers["closed"] || []).forEach((cb) => cb()); events.push("window closed"); }
}

const stubElectron = { app, BrowserWindow: FakeWindow };
// Materialize the stub as a real temp file so modern node CJS loaders accept it.
const stubFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "strake-electron-stub-")), "electron.js");
fs.writeFileSync(stubFile, "module.exports = __STRAKE_STUB__;\n");
require.cache[stubFile] = { id: stubFile, filename: stubFile, loaded: true, exports: stubElectron };
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...rest) {
  if (req === "electron") return stubFile;
  return origResolve.call(this, req, ...rest);
};

// Load the real main.js (registers app.on handlers, no side effects yet).
require(path.join(process.cwd(), "main.js"));

// Drive the lifecycle the way strake App::mark_ready + note_window_closed would.
assert(appHandlers["ready"], "main.js must register app.on(\"ready\")");
assert(appHandlers["window-all-closed"], "must handle window-all-closed");
assert(appHandlers["activate"], "must handle activate");
appHandlers["ready"].forEach((cb) => cb());
assert.strictEqual(windows.length, 1, "ready -> exactly one window");
const w = windows[0];
assert.strictEqual(w.opts.width, 365, "width 365");
assert.strictEqual(w.opts.height, 675, "height 675");
assert.strictEqual(w.resizable, false, "setResizable(false) applied");
assert.ok(w.url && w.url.includes("index.html"), "loadURL targets index.html, got: " + w.url);
w.close();
const before = quitCalled;
// Simulate non-darwin: original guards on process.platform !== "darwin".
if (process.platform !== "darwin") appHandlers["window-all-closed"].forEach((cb) => cb());
else console.log("(darwin: quit not expected, skipping)");
if (process.platform !== "darwin") assert.ok(quitCalled, "window-all-closed -> app.quit()");

console.log("PASS: ready -> createWindow(365x675, non-resizable) -> loadURL(index.html)");
console.log("PASS: closed -> window-all-closed -> quit() = " + (process.platform !== "darwin" ? quitCalled : "skipped-darwin"));
console.log("PASS: activate handler registered (re-create path, not exercised headless)");
// Static check (platform-independent): the window-all-closed handler calls app.quit().
const src = fs.readFileSync(path.join(process.cwd(), "main.js"), "utf8");
assert.ok(/window-all-closed[\s\S]*?app\.quit\(\)/.test(src), "window-all-closed handler must call app.quit()");
console.log("PASS: static check window-all-closed -> app.quit() present (covers non-darwin quit path)");
console.log("--- event trace ---");
events.forEach((e) => console.log("  " + e));
'

echo "== RESULT: headless boot OK (stub-electron lifecycle; see COMPAT.md for strake mapping) =="
