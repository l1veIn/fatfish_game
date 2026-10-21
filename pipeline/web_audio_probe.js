/* QA-only Web Audio output meter. Never included in game/web or the release ZIP.
 * Observes signals already routed to destination; does not resume, unmute or play
 * sounds, and never requests microphone access. Connected analyser branches have
 * no output connection. Use prepare_web_audio_probe.py on a candidate export. */
(function () {
	"use strict";
	const NativeContext = window.AudioContext || window.webkitAudioContext;
	const connect = AudioNode.prototype.connect, disconnect = AudioNode.prototype.disconnect;
	const contexts = [], meters = new Map();
	let maxPeak = 0, nonzeroReadings = 0;
	AudioNode.prototype.connect = function (...args) {
		const result = connect.apply(this, args);
		if (args[0] === this.context.destination && !meters.has(this)) {
			const analyser = this.context.createAnalyser();
			analyser.fftSize = 2048;
			connect.call(this, analyser);
			meters.set(this, { analyser, data: new Float32Array(analyser.fftSize) });
		}
		return result;
	};
	AudioNode.prototype.disconnect = function (...args) {
		const result = disconnect.apply(this, args);
		if (!args.length || args[0] === this.context.destination || typeof args[0] === "number") {
			const meter = meters.get(this);
			if (meter) {
				try { disconnect.call(this, meter.analyser); } catch (_) { /* Already disconnected. */ }
				meters.delete(this);
			}
		}
		return result;
	};
	class ObservedContext extends NativeContext {
		constructor(...args) { super(...args); contexts.push(this); }
	}
	window.AudioContext = ObservedContext;
	if (window.webkitAudioContext) window.webkitAudioContext = ObservedContext;
	window.addEventListener("DOMContentLoaded", () => {
		const output = document.createElement("pre");
		output.id = "audio-probe";
		output.style.cssText = "position:fixed;bottom:8px;left:8px;z-index:100;background:#111e;color:#fff;padding:12px;font:13px monospace;pointer-events:none";
		document.body.append(output);
		setInterval(() => {
			let peak = 0;
			for (const { analyser, data } of meters.values()) {
				analyser.getFloatTimeDomainData(data);
				for (const sample of data) peak = Math.max(peak, Math.abs(sample));
			}
			maxPeak = Math.max(maxPeak, peak);
			if (peak > 0.00001) nonzeroReadings++;
			output.textContent = JSON.stringify({
				contexts: contexts.map(c => ({ state: c.state, sampleRate: c.sampleRate })),
				destinationConnections: meters.size, peak, maxPeak, nonzeroReadings,
			}, null, 2);
		}, 250);
	});
}());
