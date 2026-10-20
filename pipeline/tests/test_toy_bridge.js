"use strict";
// Run with: node --test pipeline/tests/test_toy_bridge.js
const test = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const createBridge = require("../../game/web/toy_bridge.js");

function save(runs = 1, extra = {}) {
	return JSON.stringify({ version: 3, tokens: runs, total_tokens: runs * 10, runs, levels: {}, saved_at: runs * 1000, ...extra });
}
class Element {
	constructor(tag, document) {
		this.tagName = tag; this.document = document; this.children = []; this.listeners = {};
		this.style = { setProperty() {} }; this.dataset = {}; this.hidden = false; this.textContent = "";
	}
	append(...children) { children.forEach(child => this.appendChild(child)); }
	appendChild(child) { child.parent = this; this.children.push(child); return child; }
	remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); }
	setAttribute(name, value) { this[name] = value; }
	addEventListener(name, fn) { this.listeners[name] = fn; }
	focus() { this.document.activeElement = this; }
	click() { if (this.listeners.click) this.listeners.click({}); }
	querySelectorAll(tag) { return this.children.flatMap(child => [ ...(child.tagName === tag ? [child] : []), ...child.querySelectorAll(tag)]); }
	querySelector(tag) { return this.querySelectorAll(tag)[0] || null; }
}
function documentMock() {
	const doc = { hidden: false, listeners: {}, addEventListener(name, fn) { this.listeners[name] = fn; } };
	doc.createElement = tag => new Element(tag, doc);
	doc.body = doc.createElement("body"); doc.documentElement = doc.createElement("html");
	doc.getElementById = id => {
		const search = el => el.id === id ? el : el.children.map(search).find(Boolean);
		return search(doc.body);
	};
	return doc;
}
function harness(options = {}) {
	let now = 100000, nextTimer = 0, nextUUID = 0, reloaded = false;
	const timers = new Map(), calls = [], store = options.store || {};
	const doc = options.dom ? documentMock() : undefined;
	const sdk = {
		isSupport: async ability => options.abilities ? options.abilities.includes(ability) : ["getCloudStorage", "setCloudStorage", "navigate"].includes(ability),
		async getCloudStorage(keys) {
			calls.push({ type: "get", keys });
			if (options.get) return options.get(keys, store, calls);
			return keys ? Object.fromEntries(keys.filter(key => key in store).map(key => [key, store[key]])) : { ...store };
		},
		async setCloudStorage(items) {
			calls.push({ type: "set", items });
			if (options.set) await options.set(items, store, calls);
			for (const [key, value] of Object.entries(items)) {
				assert.match(key, /^[a-zA-Z0-9_-]+$/); assert.ok(!key.startsWith("__"));
				assert.ok(Buffer.byteLength(key) <= 128); assert.ok(Buffer.byteLength(value) <= 1024);
				store[key] = value;
			}
			assert.ok(Object.keys(store).length <= 128);
		},
		navigate(req) { calls.push({ type: "navigate", req }); return Promise.resolve(); },
		saveImageToAlbum(req) { calls.push({ type: "album", req }); return Promise.resolve({ localPath: "album/image.png" }); },
		onContainerChange(fn) { calls.push({ type: "listen" }); options.containerListener = fn; return () => {}; },
		getContainerState: async () => ({ deviceType: "phone", orientation: "portrait", immersive: false, safeArea: {} }),
		setContainerMode(req) { calls.push({ type: "mode", req }); return Promise.resolve(); },
	};
	const env = {
		toy: options.noSDK ? undefined : sdk,
		Date: { now: () => now },
		setTimeout(fn, ms) { const id = ++nextTimer; timers.set(id, { at: now + ms, fn }); return id; },
		clearTimeout(id) { timers.delete(id); },
		btoa: value => Buffer.from(value, "binary").toString("base64"),
		atob: value => Buffer.from(value, "base64").toString("binary"),
		crypto: {
			subtle: { digest: async (_, bytes) => createHash("sha256").update(bytes).digest() },
			randomUUID: () => "00000000-0000-0000-0000-" + String(++nextUUID).padStart(12, "0"),
		},
		document: doc,
		addEventListener() {},
		open(...args) { calls.push({ type: "open", args }); },
		location: { reload() { reloaded = true; } },
	};
	const api = createBridge(env);
	async function settle() { for (let i = 0; i < 40; i++) await Promise.resolve(); }
	async function advance(ms) {
		now += ms;
		for (let guard = 0; guard < 100; guard++) {
			await settle();
			const found = [...timers].filter(([, t]) => t.at <= now).sort((a, b) => a[1].at - b[1].at)[0];
			if (!found) break;
			timers.delete(found[0]); found[1].fn();
		}
		await settle();
	}
	const status = () => doc && doc.getElementById("toy-sync-label").textContent;
	return { api, env, store, calls, sdk, doc, advance, settle, status, options, reloaded: () => reloaded };
}
async function commit(h, value) { h.api.queueSave(value); await h.advance(30000); }
function setCalls(h) { return h.calls.filter(call => call.type === "set"); }

test("missing SDK stays local and init callback fires only once", async () => {
	const h = harness({ noSDK: true });
	let count = 0;
	assert.equal((await h.api.init(save(), () => count++)).status, "local_only");
	await h.api.init(save(2), () => count++);
	h.api.queueSave(save(3)); await h.advance(60000);
	assert.equal(count, 1); assert.equal(setCalls(h).length, 0);
});

test("UTF-8 saves are split within Toy limits; latest pending save wins and previous generation remains", async () => {
	const h = harness();
	await h.api.init(save(0));
	h.api.queueSave(save(1)); h.api.queueSave(save(2, { note: "饭".repeat(10000) }));
	await h.advance(29999); assert.equal(setCalls(h).length, 0);
	await h.advance(1); assert.equal(setCalls(h).length, 2);
	await commit(h, save(3, { note: "鱼".repeat(10000) }));
	await commit(h, save(4, { note: "菜".repeat(10000) }));
	assert.ok(Object.keys(h.store).length <= 99);
	const pointer = JSON.parse(h.store.fatfish_head);
	assert.notEqual(pointer.current.slot, pointer.previous.slot);
	const reloaded = harness({ store: { ...h.store } });
	const result = await reloaded.api.init(save(0));
	assert.equal(result.status, "restored");
	assert.equal(JSON.parse(result.save).runs, 4);
	assert.equal(JSON.parse(result.save).note.length, 10000);
});

test("partial chunk write never commits; safe retry rereads and preserves previous good generation", async () => {
	const h = harness(); await h.api.init(save(0)); await commit(h, save(1));
	const before = h.store.fatfish_head;
	h.options.set = async (items, store) => {
		if (!items.fatfish_head) {
			const key = Object.keys(items)[0]; store[key] = items[key];
			throw new Error("network lost midway");
		}
	};
	await commit(h, save(2, { note: "饭".repeat(500) }));
	assert.equal(h.store.fatfish_head, before);
	const reload = harness({ store: { ...h.store } });
	assert.equal(JSON.parse((await reload.api.init(save(0))).save).runs, 1);
	h.options.set = undefined; await h.advance(30000); await h.api.retry(); await h.advance(0);
	assert.notEqual(h.store.fatfish_head, before);
});

test("corrupted current generation recovers previous, and failed repair does not destroy that fallback", async () => {
	const h = harness(); await h.api.init(save(0)); await commit(h, save(1)); await commit(h, save(2));
	const pointer = JSON.parse(h.store.fatfish_head);
	h.store[(pointer.current.slot ? "fatfish_b_" : "fatfish_a_") + "0"] = "AAAA";
	const restored = harness({ store: { ...h.store } });
	const result = await restored.api.init(save(0));
	assert.equal(result.status, "recovered"); assert.equal(JSON.parse(result.save).runs, 1);
	restored.api.queueSave(save(5)); await restored.advance(30000);
	assert.equal(setCalls(restored).length, 0, "restoration requires Godot acknowledgement");
	restored.api.acknowledgeRestore(true);
	restored.options.set = async () => { throw new Error("offline"); };
	await commit(restored, save(3));
	const reloaded = harness({ store: { ...restored.store } });
	assert.equal(JSON.parse((await reloaded.api.init(save(0))).save).runs, 1);
});

test("bad checksums in both committed generations pause writes", async () => {
	const h = harness(); await h.api.init(save(0)); await commit(h, save(1)); await commit(h, save(2));
	h.store.fatfish_a_0 = "AAAA"; h.store.fatfish_b_0 = "AAAA";
	const reader = harness({ store: h.store });
	assert.equal((await reader.api.init(save(3))).status, "corrupt");
	await commit(reader, save(4)); assert.equal(setCalls(reader).length, 0);
});

test("capacity failure leaves the existing pointer and all its data untouched", async () => {
	const h = harness(); await h.api.init(save(0)); await commit(h, save(1));
	const before = { ...h.store };
	await commit(h, save(2, { note: "饭".repeat(20000) }));
	assert.deepEqual(h.store, before);
});

test("initial read timeout never allows later writes or accepts a late read result", async () => {
	let finish;
	const h = harness({ get: () => new Promise(resolve => { finish = resolve; }) });
	let callbacks = 0;
	const pending = h.api.init(save(1), () => callbacks++);
	await h.settle(); await h.advance(8000);
	assert.equal((await pending).status, "read_timeout");
	finish({}); await h.settle(); await commit(h, save(2));
	assert.equal(callbacks, 1); assert.equal(setCalls(h).length, 0);
});

test("rate limit imposes backoff and retry rereads cloud instead of writing immediately", async () => {
	const h = harness(); await h.api.init(save(0));
	h.options.set = async () => { throw Object.assign(new Error("busy"), { type: "http_error", code: 307044 }); };
	await commit(h, save(1));
	const count = h.calls.length;
	await h.api.retry(); assert.equal(h.calls.length, count);
	h.options.set = undefined;
	await h.advance(30000); await h.api.retry(); await h.advance(0);
	assert.ok(h.store.fatfish_head);
});

test("revision changed on another device pauses before any writes", async () => {
	const h = harness(); await h.api.init(save(0)); await commit(h, save(1));
	const foreign = harness({ store: { ...h.store } });
	await foreign.api.init(save(1)); await commit(foreign, save(3));
	Object.assign(h.store, foreign.store);
	const before = setCalls(h).length;
	await commit(h, save(2));
	assert.equal(setCalls(h).length, before);
	assert.equal(h.store.fatfish_head, foreign.store.fatfish_head);
});

test("startup conflict asks explicitly; local choice commits only after user action", async () => {
	const writer = harness(); await writer.api.init(save(0)); await commit(writer, save(4));
	const h = harness({ store: { ...writer.store }, dom: true });
	let callbacks = 0;
	const pending = h.api.init(save(3), () => callbacks++);
	await h.settle();
	assert.equal(callbacks, 0);
	const buttons = h.doc.body.querySelectorAll("button");
	assert.ok(buttons.some(button => button.textContent.includes("使用云存档")));
	buttons.find(button => button.textContent.includes("使用本机存档")).click();
	assert.equal((await pending).status, "conflict_local");
	assert.equal(callbacks, 1);
	await h.advance(30000);
	const reader = harness({ store: { ...h.store } });
	assert.equal(JSON.parse((await reader.api.init(save(0))).save).runs, 3);
});

test("cloud choice returns the selected string but failed Godot restoration blocks uploads", async () => {
	const writer = harness(); await writer.api.init(save(0)); await commit(writer, save(4));
	const h = harness({ store: { ...writer.store }, dom: true });
	const pending = h.api.init(save(3)); await h.settle();
	h.doc.body.querySelectorAll("button").find(button => button.textContent.includes("使用云存档")).click();
	assert.equal((await pending).status, "conflict_cloud");
	h.api.acknowledgeRestore(false); await commit(h, save(9));
	assert.equal(setCalls(h).length, 0);
});

test("cancel conflict leaves both saves untouched and continues locally", async () => {
	const writer = harness(); await writer.api.init(save(0)); await commit(writer, save(4));
	const h = harness({ store: { ...writer.store }, dom: true });
	const pending = h.api.init(save(3)); await h.settle();
	h.doc.body.querySelectorAll("button").find(button => button.textContent.includes("暂不选择")).click();
	assert.equal((await pending).status, "local_only");
	await commit(h, save(5)); assert.equal(setCalls(h).length, 0);
});

test("unknown cloud after a failed initial read is never overwritten by manual retry", async () => {
	const writer = harness(); await writer.api.init(save(0)); await commit(writer, save(4));
	const h = harness({ store: { ...writer.store }, dom: true, get: async () => { throw new Error("offline"); } });
	await h.api.init(save(2)); h.api.queueSave(save(3)); await h.advance(30000);
	h.options.get = undefined; await h.api.retry();
	assert.match(h.status(), /另一设备/); assert.equal(setCalls(h).length, 0);
	await h.api.retry(); assert.equal(h.reloaded(), true);
});

test("author navigation uses cached support synchronously inside the click gesture", async () => {
	const h = harness(); await h.api.prepare();
	h.api.openAuthor();
	assert.deepEqual(h.calls.at(-1), { type: "navigate", req: { type: "space", id: "2501012" } });
	const ordinary = harness({ noSDK: true }); await ordinary.api.prepare(); ordinary.api.openAuthor();
	assert.equal(ordinary.calls[0].args[0], "https://space.bilibili.com/2501012");
});

test("App container listener precedes request; resolving request is not confirmation", async () => {
	const h = harness({ dom: true, abilities: ["onContainerChange", "getContainerState", "setContainerMode", "saveImageToAlbum"] });
	await h.api.prepare(); h.api.startGesture();
	assert.ok(h.calls.findIndex(c => c.type === "listen") < h.calls.findIndex(c => c.type === "mode"));
	assert.equal(h.doc.documentElement.dataset.toyLandscape, "unconfirmed");
	h.options.containerListener({ orientation: "landscape", immersive: true, safeArea: {} });
	assert.equal(h.doc.documentElement.dataset.toyLandscape, "confirmed");
	const result = await h.api.saveImage("AAAA", "a.png");
	assert.equal(result.ok, true); assert.equal(h.calls.at(-1).type, "album");
	const tooBig = await h.api.saveImage("A".repeat(5242881), "a.png");
	assert.equal(tooBig.ok, false);
});
