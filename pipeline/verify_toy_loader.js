"use strict";
// Fault injection against an actual exported loader; no Godot gameplay or saves run.
// TOY_LOADER=... node --test pipeline/verify_toy_loader.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = process.env.TOY_LOADER;
if (!path) throw new Error("Set TOY_LOADER to the candidate index.js");
const source = fs.readFileSync(path, "utf8").split("const Features =")[1];
assert.ok(source, "Godot feature/loader boundary must exist");

function harness(options = {}) {
	let attempts = 0;
	const module = { initFS: async () => {}, initConfig() {}, copyToFS() {}, callMain() {} };
	const context = vm.createContext({
		Response, ReadableStream, Uint8Array, ArrayBuffer, console,
		setTimeout: fn => setImmediate(fn), clearTimeout: clearImmediate,
		requestAnimationFrame() {}, HTMLCanvasElement: class {},
		navigator: { language: "zh-CN" }, document: { getElementsByTagName: () => [] },
		WebAssembly: options.wasm || WebAssembly,
		Godot: options.Godot || (async () => module),
		fetch: async file => { attempts++; return options.fetch ? options.fetch(file) : new Response(new Uint8Array([1, 2, 3])); },
	});
	vm.runInContext("const Features =" + source + "\nglobalThis.subject = { Preloader, Engine, InternalConfig };", context);
	return { ...context.subject, attempts: () => attempts };
}
function brokenBody() {
	let reads = 0;
	return new Response(new ReadableStream({ pull(controller) {
		if (++reads === 1) controller.enqueue(new Uint8Array([1, 2]));
		else controller.error(new TypeError("fixture: connection interrupted"));
	} }));
}
function bounded(promise) {
	let timer;
	return Promise.race([promise, new Promise((_, reject) => {
		timer = setTimeout(() => reject(new Error("fixture: loader hung")), 1500);
	})]).finally(() => clearTimeout(timer));
}

test("partial data response rejects after bounded automatic retries", async () => {
	const h = harness({ fetch: brokenBody });
	await assert.rejects(bounded(new h.Preloader().loadPromise("index.data", 8)), /connection interrupted/);
	assert.equal(h.attempts(), 4);
});
test("interrupted data can recover on the next attempt", async () => {
	let count = 0;
	const h = harness({ fetch: () => ++count === 1 ? brokenBody() : new Response(new Uint8Array([9, 8, 7])) });
	const bytes = await bounded(new h.Preloader().loadPromise("index.data", 3));
	assert.deepEqual([...new Uint8Array(bytes)], [9, 8, 7]);
	assert.equal(h.attempts(), 2);
});
test("a missing WASM fetch rejects engine startup", async () => {
	const h = harness({ fetch: async () => { throw new Error("fixture: WASM unavailable"); } });
	await assert.rejects(bounded(new h.Engine({ executable: "index" }).init("index")), /WASM unavailable/);
	assert.equal(h.attempts(), 4);
});
test("Godot initialization rejection reaches startup caller", async () => {
	const h = harness({ Godot: async () => { throw new Error("fixture: module failed"); } });
	await assert.rejects(bounded(new h.Engine({ executable: "index" }).init("index")), /module failed/);
});
test("persistent filesystem rejection reaches startup caller", async () => {
	const h = harness({ Godot: async () => ({ initFS: async () => { throw new Error("fixture: FS failed"); } }) });
	await assert.rejects(bounded(new h.Engine({ executable: "index" }).init("index")), /FS failed/);
});
for (const streaming of [true, false]) {
	test(`WASM ${streaming ? "streaming" : "buffer"} compilation rejects engine startup`, async () => {
		const wasm = { instantiate: async () => { throw new Error("fixture: compile failed"); } };
		if (streaming) wasm.instantiateStreaming = wasm.instantiate;
		const h = harness({ wasm, Godot: config => new Promise(resolve => {
			config.instantiateWasm({}, () => resolve({ initFS: async () => {} }));
		}) });
		await assert.rejects(bounded(new h.Engine({ executable: "index" }).init("index")), /compile failed/);
	});
}
test("successful fetch and initialization still resolve", async () => {
	const h = harness();
	await bounded(new h.Engine({ executable: "index" }).init("index"));
});
