// Spec 035: a small harness that runs the real `voice()` function from app/assets/javascripts/chat.js in
// JavaScriptCore (jsc), with a fake panel, microphone, AudioContext and fetch. No libraries, no browser.
// test/javascript/voice_mute_test.rb loads: this file, then `voice()` cut out of chat.js, then the scenarios.

class FakeElement {
  constructor(name, parts = {}) {
    this.name = name;
    this.parts = parts; // selector -> element or array of elements
    this.dataset = {};
    this.attributes = {};
    this.listeners = {};
    this.classes = new Set();
    this.hidden = false;
    this.textContent = "";
    this.title = "";
    this.style = {};
    const classes = this.classes;
    this.classList = {
      toggle: (c, on) => { (on ?? !classes.has(c)) ? classes.add(c) : classes.delete(c); },
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c)
    };
  }
  querySelector(selector) { const p = this.parts[selector]; return Array.isArray(p) ? p[0] ?? null : p ?? null; }
  querySelectorAll(selector) { const p = this.parts[selector]; return Array.isArray(p) ? p : p ? [ p ] : []; }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  setAttribute(key, value) { this.attributes[key] = String(value); }
  getAttribute(key) { return this.attributes[key] ?? null; }
  closest() { return null; }
  click() { return Promise.all((this.listeners.click || []).map((fn) => fn({ target: this }))); }
}

const world = { fetches: [], received: [], getUserMediaCalls: 0, tracks: [], processor: null, played: [], contexts: 0, timers: [] };

globalThis.window = globalThis;
window.addEventListener = () => {};
globalThis.document = { querySelector: () => null, querySelectorAll: () => [] };
globalThis.setTimeout = (fn) => { world.timers.push(fn); return world.timers.length; };
globalThis.Blob = class { constructor(parts, options) { this.parts = parts; this.type = options?.type; } };

globalThis.navigator = {
  mediaDevices: {
    async getUserMedia() {
      world.getUserMediaCalls++;
      const track = { enabled: true, stopped: false, stop() { this.stopped = true; } };
      world.tracks.push(track);
      return { getAudioTracks: () => [ track ], getTracks: () => [ track ] };
    }
  }
};

window.AudioContext = class {
  constructor() { world.contexts++; this.sampleRate = 48000; this.destination = {}; }
  async resume() {}
  close() {}
  createMediaStreamSource() { return { connect() {}, disconnect() {} }; }
  createScriptProcessor() { world.processor = { connect() {}, disconnect() {} }; return world.processor; }
  async decodeAudioData(buffer) { return { buffer }; }
  createBufferSource() {
    const node = { started: false, stopped: false, connect() {}, start() { this.started = true; }, stop() { this.stopped = true; } };
    world.played.push(node);
    return node;
  }
};

let nextMessageId = 100;
globalThis.fetch = async (url, options) => {
  world.fetches.push({ url, options });
  if (url === "/director/voice/transcribe") {
    const id = ++nextMessageId;
    return { ok: true, json: async () => ({ ok: true, message: { id, author: "user", content: `utterance ${id}` } }) };
  }
  if (url === "/director/voice/speak") return { ok: true, arrayBuffer: async () => new ArrayBuffer(8) };
  return { ok: false, json: async () => ({}) };
};

function buildChat() {
  const label = new FakeElement("mute label");
  const parts = {
    "[data-voice-state]": new FakeElement("state"),
    "[data-voice-note]": new FakeElement("note"),
    ".voice-dots i": [ new FakeElement("dot"), new FakeElement("dot"), new FakeElement("dot") ],
    "[data-voice-done]": new FakeElement("done"),
    "[data-voice-mute]": new FakeElement("mute", { ".voice-mute-label": label }),
    "[data-voice-mute-status]": new FakeElement("mute status"),
    "[data-voice-stop]": new FakeElement("stop")
  };
  parts["[data-voice-note]"].textContent = "Speak; I send when you pause, or press Done.";
  parts["[data-voice-mute]"].setAttribute("aria-pressed", "false");
  label.textContent = "Mute";
  const panel = new FakeElement("panel", parts);
  panel.hidden = true;
  const start = new FakeElement("start");
  const app = new FakeElement("app", { "[data-voice-start]": start, "[data-voice-panel]": panel });
  Object.assign(app.dataset, { voice: "ready", voiceTranscribeUrl: "/director/voice/transcribe", voiceSpeakUrl: "/director/voice/speak" });
  const handlers = {};
  const chat = {
    signal: null, csrf: "token", writing: false, verifierOn: false,
    hold() {},
    on(event, fn) { (handlers[event] ||= []).push(fn); },
    receive(data) { world.received.push(data); },
    emit(event, value) { (handlers[event] || []).forEach((fn) => fn(value)); }
  };
  voice(app, chat);
  return {
    app, panel, start, chat, world,
    mute: parts["[data-voice-mute]"], muteLabel: label, status: parts["[data-voice-mute-status]"],
    stateLabel: parts["[data-voice-state]"], note: parts["[data-voice-note]"],
    doneButton: parts["[data-voice-done]"], stop: parts["[data-voice-stop]"],
    get state() { return panel.dataset.state; },
    transcribes() { return world.fetches.filter((f) => f.url === "/director/voice/transcribe"); },
    // One ScriptProcessor block is 4096 samples at 48 kHz (about 85 ms).
    feed(level, ms) {
      for (let t = 0; t < ms; t += 4096 / 48) {
        const block = new Float32Array(4096).fill(level);
        world.processor?.onaudioprocess({ inputBuffer: { getChannelData: () => block } });
      }
    },
    // The samples of a WAV sent to /transcribe (16-bit PCM after a 44-byte header).
    samples(request) {
      const view = new DataView(request.options.body.parts[0]);
      const out = new Set();
      for (let i = 44; i < view.byteLength; i += 2) out.add(view.getInt16(i, true));
      return out;
    }
  };
}

// Lets awaited fetches and promise chains finish.
async function settle() { for (let i = 0; i < 50; i++) await null; }

function level(value) { return Math.trunc(value * 0x7fff); } // as wav() writes it

const scenarios = {};
function scenario(name, fn) { scenarios[name] = fn; }
function assert(condition, message) { if (!condition) throw new Error(message); }
function assertEqual(expected, actual, message) {
  if (expected !== actual) throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
