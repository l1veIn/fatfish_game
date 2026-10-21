/* FatFish Toy integration. No account identity or credentials are requested. */
(function (root, factory) {
	"use strict";
	if (typeof module === "object" && module.exports) module.exports = factory;
	else root.FatFishToy = factory(root);
}(typeof window === "object" ? window : globalThis, function createBridge(env) {
	"use strict";
	const CHUNK_SIZE = 1000, MAX_CHUNKS = 48, INTERVAL = 30000, TIMEOUT = 8000;
	const HEAD = "fatfish_head", SLOT = ["fatfish_a_", "fatfish_b_"];
	const enc = new TextEncoder(), dec = new TextDecoder("utf-8", { fatal: true });
	const clock = () => env.Date ? env.Date.now() : Date.now();
	const timer = (fn, ms) => env.setTimeout(fn, ms);
	const clearTimer = id => env.clearTimeout(id);
	let sdk, support = {}, preparePromise, preparing = false, initialized = false, writable = false;
	let waitingRestore = false, expectedHead = "", head = null, activeMeta = null, currentSave = "", pendingSave = "";
	let flight = false, scheduled = null, lastAttempt = 0, retryAt = 0, failures = 0;
	let status = "loading", english = false, offContainer = null, desiredMode = { orientation: "landscape", immersive: true }, confirmedMode = false;
	let statusNode, retryButton, hideTimer, modal, initialCallback, initPromise;
	let containerRevision = 0, modeTimer, resizeTimer, modeButton, lastContainer;
	const messages = {
		loading: ["正在检查云存档…", "Checking cloud save…"],
		synced: ["云存档已同步", "Cloud save synced"],
		pending: ["进度已在本机保存，等待云同步", "Saved locally · cloud sync pending"],
		saving: ["正在同步云存档…", "Syncing cloud save…"],
		local_only: ["本机存档", "Local save"],
		cloud_unavailable: ["云存档暂不可用，进度保存在本机", "Cloud unavailable · progress saved locally"],
		read_timeout: ["云存档读取超时，进度保存在本机", "Cloud read timed out · progress saved locally"],
		rate_limited: ["云同步繁忙，进度已在本机保存", "Cloud busy · progress saved locally"],
		corrupt: ["云存档校验失败，已暂停同步", "Cloud save damaged · sync paused"],
		recovered: ["已恢复上一份完整云存档", "Previous complete cloud save recovered"],
		restored: ["已恢复云存档", "Cloud save restored"],
		remote_changed: ["另一设备更新了云存档；重新载入后选择存档", "Cloud changed on another device · reload to choose a save"],
		rejected: ["此云存档无法读取，已暂停同步", "Cloud save could not be loaded · sync paused"],
		too_large: ["存档超出云容量，进度保存在本机", "Cloud capacity exceeded · progress saved locally"],
		conflict_local: ["已选择本机存档，等待云同步", "Local save selected · cloud sync pending"],
		conflict_cloud: ["已选择云存档", "Cloud save selected"],
	};
	function text(pair) { return pair[english ? 1 : 0]; }
	function timeout(promise, ms = TIMEOUT) {
		let handle;
		return Promise.race([
			Promise.resolve(promise),
			new Promise((_, reject) => { handle = timer(() => reject(Object.assign(new Error("timeout"), { timeout: true })), ms); }),
		]).finally(() => clearTimer(handle));
	}
	function parseSave(value) {
		if (typeof value !== "string" || !value) return null;
		try {
			const obj = JSON.parse(value);
			if (!obj || typeof obj !== "object" || Array.isArray(obj)) return null;
			if (!Number.isInteger(obj.version) || obj.version < 1) return null;
			if (!["tokens", "total_tokens", "runs"].every(k => Number.isFinite(obj[k]) && obj[k] >= 0)) return null;
			return obj;
		} catch (_) { return null; }
	}
	function compact(value) {
		const parsed = parseSave(value);
		if (!parsed) throw new Error("invalid save");
		return JSON.stringify(parsed);
	}
	function canonical(value) {
		const normalize = obj => Array.isArray(obj) ? obj.map(normalize) :
			obj && typeof obj === "object" ? Object.fromEntries(Object.keys(obj).sort().filter(k => k !== "saved_at").map(k => [k, normalize(obj[k])])) : obj;
		return JSON.stringify(normalize(parseSave(value)));
	}
	function progressed(value) {
		const obj = parseSave(value);
		return !!(obj && (obj.runs > 0 || obj.total_tokens > 0 || obj.tokens > 0 || obj.ending_seen));
	}
	function equal(a, b) { return canonical(a) === canonical(b); }
	async function digest(bytes) {
		const hash = await env.crypto.subtle.digest("SHA-256", bytes);
		return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, "0")).join("");
	}
	function base64(bytes) {
		let raw = "";
		for (const byte of bytes) raw += String.fromCharCode(byte);
		return env.btoa(raw);
	}
	function unbase64(value) {
		const raw = env.atob(value);
		return Uint8Array.from(raw, c => c.charCodeAt(0));
	}
	function validMeta(meta) {
		return meta && meta.v === 1 && (meta.slot === 0 || meta.slot === 1) &&
			typeof meta.rev === "string" && /^[a-zA-Z0-9-]{8,100}$/.test(meta.rev) &&
			Number.isInteger(meta.count) && meta.count > 0 && meta.count <= MAX_CHUNKS &&
			Number.isInteger(meta.bytes) && meta.bytes > 0 && meta.bytes <= MAX_CHUNKS * CHUNK_SIZE * 3 / 4 &&
			typeof meta.hash === "string" && /^[a-f0-9]{64}$/.test(meta.hash);
	}
	function parseHead(raw) {
		if (!raw) return null;
		try {
			const value = JSON.parse(raw);
			if (value.v !== 1 || !validMeta(value.current) || (value.previous && !validMeta(value.previous))) throw new Error("invalid head");
			return value;
		} catch (_) { throw Object.assign(new Error("corrupt head"), { corrupt: true }); }
	}
	async function decodeSlot(all, meta) {
		if (!validMeta(meta)) throw new Error("invalid metadata");
		let packed = "";
		for (let i = 0; i < meta.count; i++) {
			const value = all[SLOT[meta.slot] + i];
			if (typeof value !== "string" || value.length > CHUNK_SIZE || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new Error("missing chunk");
			packed += value;
		}
		const bytes = unbase64(packed);
		if (bytes.length !== meta.bytes || await digest(bytes) !== meta.hash) throw new Error("checksum mismatch");
		const value = dec.decode(bytes);
		if (!parseSave(value)) throw new Error("invalid save");
		return value;
	}
	async function readRemote() {
		const all = await timeout(sdk.getCloudStorage());
		if (!all || typeof all !== "object" || Array.isArray(all)) throw new Error("invalid cloud response");
		const raw = all[HEAD] || "", parsed = parseHead(raw);
		if (!parsed) return { raw, head: null, save: "", recovered: false };
		try {
			return { raw, head: parsed, save: await decodeSlot(all, parsed.current), recovered: false };
		} catch (_) {
			if (parsed.previous) {
				try { return { raw, head: parsed, save: await decodeSlot(all, parsed.previous), recovered: true }; }
				catch (_) { /* Neither committed generation is complete. Never replace it automatically. */ }
			}
			throw Object.assign(new Error("no complete cloud generation"), { corrupt: true });
		}
	}
	function ui() {
		if (!env.document || statusNode) return;
		statusNode = env.document.createElement("aside");
		statusNode.id = "toy-sync";
		statusNode.setAttribute("aria-live", "polite");
		const label = env.document.createElement("span");
		label.id = "toy-sync-label";
		retryButton = env.document.createElement("button");
		retryButton.type = "button";
		retryButton.addEventListener("click", () => { void retry(); });
		statusNode.append(label, retryButton);
		env.document.body.appendChild(statusNode);
	}
	function setStatus(value) {
		status = value;
		ui();
		if (!statusNode) return;
		clearTimer(hideTimer);
		statusNode.hidden = false;
		env.document.getElementById("toy-sync-label").textContent = text(messages[value] || messages.cloud_unavailable);
		const actionable = ["cloud_unavailable", "read_timeout", "rate_limited", "remote_changed"].includes(value);
		retryButton.hidden = !actionable;
		retryButton.textContent = value === "remote_changed" ? text(["重新载入", "Reload"]) : text(["重试", "Retry"]);
		retryButton.disabled = clock() < retryAt;
		if (["synced", "restored", "recovered", "conflict_cloud", "local_only"].includes(value))
			hideTimer = timer(() => { if (statusNode) statusNode.hidden = true; }, 6000);
		if (retryButton.disabled) timer(() => { if (retryButton) retryButton.disabled = false; }, Math.max(0, retryAt - clock()));
	}
	function failure(error) {
		writable = false;
		failures++;
		retryAt = clock() + Math.min(300000, INTERVAL * (2 ** Math.min(failures - 1, 4)));
		setStatus(error && error.corrupt ? "corrupt" : error && Number(error.code) === 307044 ? "rate_limited" : error && error.timeout ? "read_timeout" : "cloud_unavailable");
	}
	function applyContainer(state) {
		if (!state || !env.document) return;
		lastContainer = state;
		const style = env.document.documentElement.style, safe = state.safeArea || {};
		for (const side of ["top", "right", "bottom", "left"])
			style.setProperty("--toy-safe-" + side, Math.max(0, Number(safe[side]) || 0) + "px");
		if (state.deviceType) env.document.documentElement.dataset.toyDevice = state.deviceType;
		confirmedMode = !!(desiredMode && (desiredMode.orientation === "auto" || state.orientation === desiredMode.orientation) && state.immersive === desiredMode.immersive);
		env.document.documentElement.dataset.toyLandscape = confirmedMode ? "confirmed" : "unconfirmed";
		if (confirmedMode) clearTimer(modeTimer);
		updateModeButton();
	}
	async function prepare() {
		if (preparePromise && (preparing || sdk === env.toy)) return preparePromise;
		preparing = true;
		preparePromise = (async () => {
			// Do not let a blocked SDK request delay engine loading indefinitely.
			if (!env.toy && env.document) {
				const until = clock() + 2000;
				while (!env.toy && clock() < until) await new Promise(resolve => timer(resolve, 50));
			}
			sdk = env.toy;
			if (!sdk || typeof sdk.isSupport !== "function") return;
			const abilities = ["navigate", "saveImageToAlbum", "getCloudStorage", "setCloudStorage", "onContainerChange", "getContainerState", "setContainerMode"];
			await Promise.all(abilities.map(async ability => {
				try { support[ability] = await timeout(sdk.isSupport(ability), 2000) === true; }
				catch (_) { support[ability] = false; }
			}));
			if (support.onContainerChange) {
				try { offContainer = sdk.onContainerChange(state => { containerRevision++; applyContainer(state); }); }
				catch (_) { support.onContainerChange = false; }
			}
			// Enter the App's landscape immersive container as soon as its SDK is ready.
			// This also runs when the async SDK script arrives after the initial timeout.
			requestMode();
			await refreshContainer();
		})().finally(() => { preparing = false; });
		return preparePromise;
	}
	function describe(value) {
		const data = parseSave(value) || {};
		const date = Number(data.saved_at) > 0 ? new Date(data.saved_at * 1000).toLocaleString(english ? "en" : "zh-CN") : text(["时间未知", "Unknown date"]);
		return text([`已吃 ${data.runs || 0} 顿 · 累计 ${data.total_tokens || 0} 饭票\n${date}`,
			`${data.runs || 0} meals · ${data.total_tokens || 0} lifetime tickets\n${date}`]);
	}
	function chooseSave(local, remote) {
		return new Promise(resolve => {
			if (!env.document) { resolve("cancel"); return; }
			modal = env.document.createElement("div");
			modal.className = "toy-dialog-backdrop";
			const panel = env.document.createElement("section");
			panel.className = "toy-dialog";
			panel.setAttribute("role", "dialog");
			panel.setAttribute("aria-modal", "true");
			panel.setAttribute("aria-labelledby", "toy-conflict-title");
			const title = env.document.createElement("h2");
			title.id = "toy-conflict-title";
			title.textContent = text(["选择继续使用的存档", "Choose a save to continue"]);
			const note = env.document.createElement("p");
			note.textContent = text(["本机与云端进度不同。选择后将以这份进度继续；原本机存档会保留备份。",
				"Local and cloud progress differ. Continue with one save; the previous local save will be backed up."]);
			panel.append(title, note);
			for (const [choice, value, label] of [["local", local, ["使用本机存档", "Use local save"]], ["cloud", remote, ["使用云存档", "Use cloud save"]]]) {
				const button = env.document.createElement("button");
				button.type = "button";
				button.textContent = text(label) + "\n" + describe(value);
				button.addEventListener("click", () => { modal.remove(); modal = null; resolve(choice); });
				panel.appendChild(button);
			}
			const localOnly = env.document.createElement("button");
			localOnly.type = "button";
			localOnly.textContent = text(["暂不选择，只玩本机存档", "Keep both · play locally"]);
			localOnly.addEventListener("click", () => { modal.remove(); modal = null; resolve("cancel"); });
			panel.appendChild(localOnly);
			panel.addEventListener("keydown", event => {
				if (event.key !== "Tab") return;
				const buttons = Array.from(panel.querySelectorAll("button"));
				const index = buttons.indexOf(env.document.activeElement);
				event.preventDefault();
				buttons[(index + (event.shiftKey ? buttons.length - 1 : 1)) % buttons.length].focus();
			});
			modal.appendChild(panel);
			env.document.body.appendChild(modal);
			panel.querySelector("button").focus();
		});
	}
	async function initialize(local, callback) {
		currentSave = parseSave(local) ? compact(local) : "";
		initialCallback = callback;
		lastAttempt = clock();
		setStatus("loading");
		let result = { save: "", status: "local_only" };
		try {
			await prepare();
			if (!support.getCloudStorage || !support.setCloudStorage || !env.crypto || !env.crypto.subtle) {
				setStatus("local_only");
			} else {
				const remote = await readRemote();
				expectedHead = remote.raw;
				head = remote.head;
				activeMeta = head ? (remote.recovered ? head.previous : head.current) : null;
				writable = true;
				if (!remote.save || (currentSave && equal(currentSave, remote.save))) {
					result.status = remote.recovered ? "recovered" : "synced";
					setStatus(result.status);
					if (!remote.save && progressed(currentSave)) pendingSave = currentSave;
				} else if (!progressed(currentSave)) {
					result = { save: remote.save, status: remote.recovered ? "recovered" : "restored" };
				} else {
					const choice = await chooseSave(currentSave, remote.save);
					if (choice === "cloud") result = { save: remote.save, status: remote.recovered ? "recovered" : "conflict_cloud" };
					else if (choice === "local") {
						pendingSave = currentSave;
						result.status = "conflict_local";
						setStatus("conflict_local");
					} else { writable = false; result.status = "local_only"; setStatus("local_only"); }
				}
				if (result.save) {
					waitingRestore = true;
					writable = false;
					currentSave = result.save;
					setStatus(result.status);
				}
			}
		} catch (error) {
			failure(error);
			result.status = status;
		}
		initialized = true;
		if (typeof initialCallback === "function") {
			const done = initialCallback;
			initialCallback = null;
			done(JSON.stringify(result));
		}
		schedule();
		return result;
	}
	function schedule() {
		if (!initialized || !writable || waitingRestore || flight || !pendingSave || scheduled !== null) return;
		scheduled = timer(() => { scheduled = null; void flush(); }, Math.max(0, lastAttempt + INTERVAL - clock(), retryAt - clock()));
	}
	async function makeGeneration(value, slot) {
		const bytes = enc.encode(compact(value)), packed = base64(bytes);
		if (packed.length > CHUNK_SIZE * MAX_CHUNKS) throw Object.assign(new Error("save capacity"), { capacity: true });
		const rev = env.crypto.randomUUID ? env.crypto.randomUUID() : clock().toString(36) + "-" + Math.random().toString(36).slice(2);
		const meta = { v: 1, rev, slot, count: Math.ceil(packed.length / CHUNK_SIZE), bytes: bytes.length, hash: await digest(bytes), time: clock() };
		const items = {};
		for (let i = 0; i < meta.count; i++) items[SLOT[slot] + i] = packed.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE);
		items[SLOT[slot] + "meta"] = JSON.stringify(meta);
		return { meta, items };
	}
	function changedRemote() {
		writable = false;
		setStatus("remote_changed");
	}
	async function flush() {
		if (!initialized || !writable || waitingRestore || flight || !pendingSave) return;
		if (clock() < Math.max(lastAttempt + INTERVAL, retryAt)) { schedule(); return; }
		flight = true;
		lastAttempt = clock();
		const value = pendingSave;
		setStatus("saving");
		try {
			let found = await timeout(sdk.getCloudStorage([HEAD]));
			if ((found[HEAD] || "") !== expectedHead) { changedRemote(); return; }
			const generation = await makeGeneration(value, activeMeta ? 1 - activeMeta.slot : 0);
			await timeout(sdk.setCloudStorage(generation.items));
			// Recheck both ownership and the old pointer before committing. Toy has
			// no compare-and-swap API; a final read also detects a competing commit.
			found = await timeout(sdk.getCloudStorage([HEAD, SLOT[generation.meta.slot] + "meta"]));
			if ((found[HEAD] || "") !== expectedHead || found[SLOT[generation.meta.slot] + "meta"] !== JSON.stringify(generation.meta)) {
				changedRemote(); return;
			}
			const next = { v: 1, current: generation.meta, previous: activeMeta };
			const serialized = JSON.stringify(next);
			await timeout(sdk.setCloudStorage({ [HEAD]: serialized }));
			found = await timeout(sdk.getCloudStorage([HEAD]));
			if (found[HEAD] !== serialized) { changedRemote(); return; }
			expectedHead = serialized;
			head = next;
			activeMeta = next.current;
			if (pendingSave === value) pendingSave = "";
			failures = 0;
			retryAt = 0;
			setStatus(pendingSave ? "pending" : "synced");
		} catch (error) {
			if (error && error.capacity) { writable = false; setStatus("too_large"); }
			else failure(error);
		} finally {
			flight = false;
			schedule();
		}
	}
	async function retry() {
		if (status === "remote_changed") {
			if (env.location && typeof env.location.reload === "function") env.location.reload();
			return;
		}
		if (flight || waitingRestore || clock() < retryAt || !support.getCloudStorage || !support.setCloudStorage) return;
		flight = true;
		setStatus("loading");
		try {
			const remote = await readRemote();
			if (remote.raw !== expectedHead && remote.save && !equal(currentSave, remote.save)) { changedRemote(); return; }
			expectedHead = remote.raw;
			head = remote.head;
			activeMeta = head ? (remote.recovered ? head.previous : head.current) : null;
			writable = true;
			failures = 0;
			retryAt = 0;
			if (currentSave && (!remote.save || !equal(currentSave, remote.save))) pendingSave = currentSave;
			else pendingSave = "";
			setStatus(pendingSave ? "pending" : "synced");
		} catch (error) { failure(error); }
		finally { flight = false; schedule(); }
	}
	function updateModeButton(show = false) {
		if (!env.document) return;
		if (!modeButton && show) {
			modeButton = env.document.createElement("button");
			modeButton.id = "toy-fullscreen";
			modeButton.type = "button";
			modeButton.addEventListener("click", () => setFullscreen(true));
			env.document.body.appendChild(modeButton);
		}
		if (modeButton) {
			modeButton.textContent = text(["全屏", "Fullscreen"]);
			modeButton.hidden = isFullscreen();
		}
	}
	function isFullscreen() {
		return !!((lastContainer && lastContainer.immersive && lastContainer.orientation === "landscape") ||
			(env.document && env.document.fullscreenElement));
	}
	function requestMode() {
		if (!sdk || !support.setContainerMode) return false;
		clearTimer(modeTimer);
		confirmedMode = false;
		try {
			Promise.resolve(sdk.setContainerMode(desiredMode)).catch(() => updateModeButton(true));
		} catch (_) { updateModeButton(true); }
		// A fulfilled Promise<void> is not a mode confirmation. Keep a retry available.
		modeTimer = timer(() => { if (!confirmedMode && desiredMode.immersive) updateModeButton(true); }, 2500);
		return true;
	}
	async function refreshContainer() {
		if (!sdk || !support.getContainerState) return;
		const revision = containerRevision;
		try {
			const state = await timeout(sdk.getContainerState(), 2000);
			if (revision === containerRevision) applyContainer(state);
		} catch (_) { /* The actual DOM viewport remains authoritative for canvas size. */ }
	}
	function setFullscreen(on) {
		desiredMode = { orientation: on ? "landscape" : "auto", immersive: on };
		if (!requestMode() && env.document) {
			try {
				const result = on ? env.document.documentElement.requestFullscreen?.() : env.document.exitFullscreen?.();
				Promise.resolve(result).catch(() => updateModeButton(true));
			} catch (_) { updateModeButton(true); }
			if (on) updateModeButton(true);
		}
		return true;
	}
	function startGesture() {
		desiredMode = { orientation: "landscape", immersive: true };
		if (support.setContainerMode) requestMode();
		else if (env.matchMedia && env.matchMedia("(pointer: coarse)").matches) setFullscreen(true);
		void prepare();
		const canvas = env.document && env.document.getElementById("canvas");
		if (canvas) canvas.focus();
	}
	function openAuthor() {
		if (sdk && support.navigate) {
			try {
				timeout(sdk.navigate({ type: "space", id: "2501012" }), 2000).catch(() => showAuthorFallback());
				return;
			} catch (_) { /* Keep the fallback in the original gesture when possible. */ }
		}
		if (typeof env.open === "function") env.open("https://space.bilibili.com/2501012", "_blank", "noopener,noreferrer");
	}
	function showAuthorFallback() {
		if (!env.document) return;
		ui();
		clearTimer(hideTimer);
		statusNode.hidden = false;
		const label = env.document.getElementById("toy-sync-label");
		label.textContent = text(["点击访问作者：", "Visit the author: "]);
		const link = env.document.createElement("a");
		link.href = "https://space.bilibili.com/2501012";
		link.target = "_blank";
		link.rel = "noopener noreferrer";
		link.textContent = "夸夸家族族长";
		label.appendChild(link);
		retryButton.hidden = true;
	}
	function download(data, filename) {
		const raw = data.replace(/^data:image\/png;base64,/, "");
		const blob = new env.Blob([unbase64(raw)], { type: "image/png" });
		const url = env.URL.createObjectURL(blob);
		const link = env.document.createElement("a");
		link.href = url;
		link.download = String(filename || "fatfish-keepsake.png").replace(/[^a-zA-Z0-9_.-]/g, "_");
		env.document.body.appendChild(link);
		link.click();
		link.remove();
		timer(() => env.URL.revokeObjectURL(url), 60000);
	}
	async function saveImage(data, filename, callback) {
		let result;
		try {
			if (typeof data !== "string" || !data.length) throw new Error("empty image");
			if (sdk && support.saveImageToAlbum) {
				if (data.length > 5242880) throw new Error(text(["图片过大，无法保存到相册", "Image is too large to save to the album"]));
				await timeout(sdk.saveImageToAlbum({ base64Data: data, hintMsg: text(["保存大肥鱼纪念饭票", "Save your FatFish keepsake"]) }), 30000);
				result = { ok: true, message: text(["饭票已保存到相册", "Keepsake saved to your album"]) };
			} else {
				download(data, filename);
				result = { ok: true, message: text(["已发起饭票下载，请查看浏览器下载记录", "Keepsake download started · check your browser downloads"]) };
			}
		} catch (error) {
			result = { ok: false, message: text(["保存未完成，请重试", "Save did not complete. Please try again."]) };
		}
		if (typeof callback === "function") callback(JSON.stringify(result));
		return result;
	}
	const api = {
		prepare, startGesture, setFullscreen, isFullscreen, openAuthor, saveImage,
		init(local, callback) {
			if (!initPromise) initPromise = initialize(local, callback);
			return initPromise;
		},
		queueSave(value) {
			if (!parseSave(value)) return;
			currentSave = compact(value);
			if (waitingRestore) return;
			pendingSave = currentSave;
			if (writable) setStatus("pending");
			schedule();
		},
		acknowledgeRestore(ok) {
			if (!waitingRestore) return;
			waitingRestore = false;
			writable = ok === true;
			if (!writable) { pendingSave = ""; setStatus("rejected"); }
			schedule();
		},
		disableCloud() {
			writable = false;
			waitingRestore = false;
			pendingSave = "";
			clearTimer(scheduled);
			scheduled = null;
			setStatus("rejected");
		},
		setLanguage(locale) {
			english = String(locale).toLowerCase().startsWith("en");
			if (env.document) env.document.documentElement.lang = english ? "en" : "zh-CN";
			setStatus(status);
			updateModeButton();
		},
		retry,
	};
	if (env.document && env.addEventListener) {
		// Browsers can emit compatibility mouse events without Godot's emulation ID.
		// Keep native touch events; discard only the extra canvas mouse stream.
		let touchMouseUntil = 0;
		const onCanvas = event => event.target && event.target.id === "canvas";
		for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"])
			env.addEventListener(type, event => { if (onCanvas(event)) touchMouseUntil = clock() + 800; }, true);
		for (const type of ["pointerdown", "pointermove"])
			env.addEventListener(type, event => {
				if (onCanvas(event) && event.pointerType === "mouse" && !event.sourceCapabilities?.firesTouchEvents) touchMouseUntil = 0;
			}, true);
		for (const type of ["mousedown", "mousemove", "mouseup"])
			env.addEventListener(type, event => {
				if (onCanvas(event) && (event.sourceCapabilities?.firesTouchEvents || clock() < touchMouseUntil)) {
					event.stopImmediatePropagation();
					if (event.cancelable) event.preventDefault();
				}
			}, true);
		env.document.addEventListener("visibilitychange", () => {
			if (env.document.hidden) void flush();
		});
		env.document.addEventListener("fullscreenchange", () => updateModeButton(true));
		env.addEventListener("resize", () => {
			clearTimer(resizeTimer);
			resizeTimer = timer(refreshContainer, 150);
		});
		env.addEventListener("pagehide", () => { void flush(); });
		env.addEventListener("unload", () => { if (typeof offContainer === "function") offContainer(); });
	}
	return api;
}));
