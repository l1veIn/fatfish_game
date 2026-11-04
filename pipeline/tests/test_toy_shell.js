"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const html = fs.readFileSync("game/web/toy_shell.html", "utf8");
const script = html.match(/<script>\s*(const GODOT_CONFIG =[\s\S]*?)<\/script>/)[1]
	.replace("$GODOT_CONFIG", "{}").replace("$GODOT_THREADS_ENABLED", "false");
function harness(missing = [], size = {width: 1280, height: 720}, dpr = 1) {
	const nodes = {}, timers = new Map(); let next = 0, progress, resolve, reject, ready, reloaded = false;
	for (const id of ["status", "status-notice", "status-progress", "start-button", "retry-load", "canvas", "game"]) {
		nodes[id] = { hidden: ["start-button", "retry-load"].includes(id), textContent: "", listeners: {},
			addEventListener(type, callback) { this.listeners[type] = callback; },
			removeAttribute() {}, focus() {}, getBoundingClientRect: () => size };
	}
	class Engine {
		static getMissingFeatures() { return missing; }
		startGame(options) { progress = options.onProgress; return new Promise((a, b) => { resolve = a; reject = b; }); }
	}
	const context = vm.createContext({ Engine, navigator: { language: "zh-CN" },
		console: { error() {} }, document: { getElementById: id => nodes[id], documentElement: {} },
		window: { devicePixelRatio: dpr, addEventListener: (_, callback) => { ready = callback; }, location: { reload: () => { reloaded = true; } } },
		ResizeObserver: class { observe() {} },
		setTimeout: fn => { const id = ++next; timers.set(id, fn); return id; }, clearTimeout: id => timers.delete(id) });
	vm.runInContext(script, context); ready();
	return { nodes, timers, progress: (...args) => progress(...args), resolve: () => resolve(), reject: e => reject(e), reloaded: () => reloaded };
}
async function settle() { for (let i = 0; i < 5; i++) await Promise.resolve(); }
test("stalled downloads offer reload and recover when progress resumes", async () => {
	const h = harness(); h.progress(5000000, 80000000);
	assert.match(h.nodes["status-notice"].textContent, /5.0 \/ 80.0 MB/);
	[...h.timers.values()][0]();
	assert.equal(h.nodes["retry-load"].hidden, false);
	assert.match(h.nodes["status-notice"].textContent, /没有进展/);
	h.progress(6000000, 80000000);
	assert.equal(h.nodes["retry-load"].hidden, true);
	assert.match(h.nodes["status-notice"].textContent, /6.0 \/ 80.0 MB/);
	h.resolve(); await settle();
	assert.equal(h.nodes["start-button"].hidden, false);
	assert.equal(h.nodes["retry-load"].hidden, true);
	assert.equal(h.timers.size, 0);
});
test("failed startup replaces endless progress with a working reload button", async () => {
	const h = harness(); h.reject(new TypeError("fixture: network error")); await settle();
	assert.match(h.nodes["status-notice"].textContent, /资源加载失败/);
	assert.equal(h.nodes["status-progress"].hidden, true);
	assert.equal(h.nodes["retry-load"].hidden, false);
	h.nodes["retry-load"].listeners.click(); assert.equal(h.reloaded(), true);
	assert.equal(h.timers.size, 0);
});
test("unsupported browser shows a terminal explanation without loading", () => {
	const h = harness(["WebGL2"]);
	assert.match(h.nodes["status-notice"].textContent, /WebGL2/);
	assert.equal(h.nodes["status-progress"].hidden, true);
});
test("wide mobile canvas retains the viewport ratio at bounded GPU resolution", () => {
	const h = harness([], {width: 1328, height: 610}, 2);
	assert.equal(h.nodes.canvas.width, 1920);
	assert.equal(h.nodes.canvas.height, 882);
	assert.ok(Math.abs(h.nodes.canvas.width / h.nodes.canvas.height - 1328 / 610) < 0.002);
});
