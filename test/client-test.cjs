// Contract tests in a VM with a small DOM/canvas double, without network access.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

let clock = 10_000;
const documentListeners = {};
const windowListeners = {};
const elements = {};
const drawCalls = [];
const intervals = new Map();
let nextInterval = 0;
let patterns = 0;
let images = 0;
let nextFrame;
const context = {
  setTransform() {}, fillRect() {}, fillText() {},
  createPattern() { patterns++; return {}; },
  drawImage(...args) { drawCalls.push(args); },
  save() { throw new Error('Canvas save stack must not grow'); },
};
class Element {
  constructor(tagName = 'DIV') {
    this.tagName = tagName;
    this.listeners = {};
    this.children = [];
    this.attributes = {};
    const classes = new Set();
    this.classList = {
      add: name => classes.add(name),
      remove: name => classes.delete(name),
      contains: name => classes.has(name),
    };
    this.value = '';
    this.textContent = '';
    this.scrollTop = this.scrollHeight = this.clientHeight = 0;
  }
  set innerHTML(_value) { throw new Error('Untrusted text must never use innerHTML'); }
  setAttribute(name, value) { this.attributes[name] = value; }
  setPointerCapture(id) { this.capturedPointer = id; }
  addEventListener(type, callback) { this.listeners[type] = callback; }
  fire(type, values = {}) {
    this.listeners[type]?.({ type, currentTarget: this, pointerId: 1, pointerType: 'touch', button: 0,
      detail: 1, preventDefault() {}, ...values });
  }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); }
  get firstChild() { return this.children[0]; }
  focus() { document.activeElement = this; }
  blur() { document.activeElement = null; }
  getContext() { return context; }
  getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; }
}
for (const id of ['join-screen', 'join-form', 'nickname', 'join-button', 'join-status', 'join-error',
  'chat-panel', 'chat-form', 'chat-input', 'chat-history', 'chat-status', 'player-name', 'game-help',
  'mobile-controls', 'touch-chat', 'chat-close', 'touch-up', 'touch-left', 'touch-right',
  'touch-stop', 'touch-reset', 'touch-fire']) {
  elements[id] = new Element(id.includes('input') || id === 'nickname' ? 'INPUT' : 'DIV');
}
const body = new Element('BODY');
const document = {
  body, activeElement: null,
  getElementById: id => elements[id],
  createElement: tag => new Element(tag.toUpperCase()),
  createTextNode: text => ({ textContent: text }),
  addEventListener: (type, callback) => { documentListeners[type] = callback; },
};
const sockets = [];
class Socket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSED = 3;
  constructor(url) { this.url = url; this.readyState = 0; this.sent = []; sockets.push(this); }
  open() { this.readyState = 1; this.onopen(); }
  send(packet) { this.sent.push(packet); }
  message(type, value) { this.onmessage({ data: `${type}:${JSON.stringify(value)}` }); }
  disconnect() { this.readyState = 3; this.onclose({ code: 1006 }); }
}
class Image {
  constructor() { images++; this.complete = true; this.naturalWidth = this.naturalHeight = 100; }
}
const window = {
  innerWidth: 800, innerHeight: 600, location: { protocol: 'https:', host: 'game.example' },
  addEventListener(type, callback) { windowListeners[type] = callback; },
  requestAnimationFrame(callback) { nextFrame = callback; },
  setInterval(callback, delay) { assert.equal(delay, 70); intervals.set(++nextInterval, callback); return nextInterval; },
  clearInterval(id) { intervals.delete(id); },
};
class FakeDate extends Date { static now() { return clock; } }
const sandbox = vm.createContext({ document, window, WebSocket: Socket, Image, Date: FakeDate, console });
vm.runInContext(fs.readFileSync(path.join(__dirname, '../public/application.js'), 'utf8'), sandbox);
documentListeners.DOMContentLoaded();
const canvas = body.children[0];
const frame = () => { drawCalls.length = 0; nextFrame(); };
const repeatControls = () => { clock += 70; for (const callback of [...intervals.values()]) callback(); };
const key = value => documentListeners.keydown({ key: value, preventDefault() {} });
const state = (otherX = 100, respawn = 0) => ({
  id: [1, 2, 3], name: ['Ala', 'Ola', 'Far'], coordinates: [[0, 0], [otherX, 0], [99_999, 99_999]],
  sizes: [[100, 100], [100, 100], [100, 100]], frames: [0, 0, 0], rotates: [0, 0, 0],
  shooted: [0, 0, 0], respawns: [0, respawn, 0], bullets: [], bonuses: [], tick: 1,
});

assert.equal(images, 103, 'Shared image resources are loaded once');
const socket = sockets[0];
assert.equal(socket.url, 'wss://game.example/ws');
socket.open();
elements.nickname.value = 'Ala';
elements['join-form'].fire('submit');
assert.deepEqual(socket.sent, ['i', 'nAla']);
socket.message('i', 1);
assert(!elements['join-screen'].hidden, 'A legacy ID must not accept the player');
socket.message('a', { id: 1, name: 'Ala' });
assert(elements['join-screen'].hidden);
assert.equal(elements['mobile-controls'].hidden, false);
assert.deepEqual(socket.sent.slice(-2), ['s', 'j']);
socket.message('j', state());
assert.equal(window.char.numer, 0);
for (let index = 0; index < 120; index++) { clock += 16; frame(); }
assert.equal(socket.sent.filter(packet => packet === 'j').length, 1, 'Rendering must not poll snapshots');
assert.equal(patterns, 1, 'The background pattern is reused');
assert.equal(drawCalls.length, 2, 'Offscreen sprites are culled');
console.log('PASS client: accepted join, server push, cached assets/background, offscreen culling');

socket.message('j', state(200));
clock += 25;
frame();
assert.equal(drawCalls[1][1] - drawCalls[0][1], 150, 'Positions interpolate over 50 ms');
socket.message('j', state(240, 1));
frame();
assert.equal(drawCalls[1][1] - drawCalls[0][1], 240, 'Respawn positions must snap without interpolation');
console.log('PASS client: interpolation and respawn handling');

const left = elements['touch-left'];
const up = elements['touch-up'];
left.fire('pointerdown', { pointerId: 11 });
up.fire('pointerdown', { pointerId: 12 });
assert.deepEqual(socket.sent.slice(-2), ['l', 't']);
assert.equal(left.capturedPointer, 11);
assert.equal(intervals.size, 2);
repeatControls();
assert.deepEqual(socket.sent.slice(-2), ['l', 't'], 'Two held controls must repeat independently');
left.fire('pointerup', { pointerId: 11 });
repeatControls();
assert.equal(socket.sent.at(-1), 't');
assert.equal(intervals.size, 1, 'Releasing one finger must not stop the other');

const x = 650 - window.map.move_x;
const y = 500 - window.map.move_y;
canvas.fire('pointerdown', { pointerId: 13, clientX: 650, clientY: 500 });
canvas.fire('pointerup', { pointerId: 13, clientX: 650, clientY: 500 });
assert.equal(socket.sent.at(-1), `p${x},${y}`, 'A second finger aims while movement is held');
assert.equal(intervals.size, 1);
up.fire('pointercancel', { pointerId: 12 });
assert.equal(intervals.size, 0);
left.fire('pointerdown', { pointerId: 14 });
left.fire('lostpointercapture', { pointerId: 14 });
assert.equal(intervals.size, 0, 'Losing touch capture stops movement');
up.fire('pointerdown', { pointerId: 15 });
windowListeners.blur();
assert.equal(intervals.size, 0, 'Backgrounding the page stops movement');
up.fire('pointerdown', { pointerId: 19 });
document.hidden = true;
documentListeners.visibilitychange();
document.hidden = false;
assert.equal(intervals.size, 0, 'A hidden tab stops held controls');
const beforeCancelledTap = socket.sent.length;
canvas.fire('pointerdown', { pointerId: 20, clientX: 400, clientY: 300 });
canvas.fire('pointercancel', { pointerId: 20 });
canvas.fire('pointerup', { pointerId: 20, clientX: 400, clientY: 300 });
assert.equal(socket.sent.length, beforeCancelledTap, 'A cancelled touch must not fire');
elements['touch-stop'].fire('pointerdown', { pointerId: 16 });
assert.equal(socket.sent.at(-1), 'b');
elements['touch-reset'].fire('pointerdown', { pointerId: 17 });
assert.equal(socket.sent.at(-1), 'q');
elements['touch-fire'].fire('pointerdown', { pointerId: 18 });
assert.equal(socket.sent.at(-1), 'p290,50', 'Fire button aims at the nearest visible opponent');
socket.message('j', state(99_999));
frame();
elements['touch-fire'].fire('pointerdown', { pointerId: 21 });
assert.equal(socket.sent.at(-1), 'p500,50', 'With no visible opponent, shoot in the facing direction');
elements['touch-right'].fire('click', { detail: 0 });
assert.equal(socket.sent.at(-1), 'r', 'Keyboard or assistive activation is supported');

left.fire('pointerdown', { pointerId: 22 });
elements['touch-chat'].fire('click');
assert.equal(intervals.size, 0, 'Opening chat stops held controls');
assert(elements['chat-panel'].classList.contains('chat-open'));
assert(elements['mobile-controls'].classList.contains('chat-active'));
assert.equal(elements['touch-chat'].attributes['aria-expanded'], 'true');
assert.equal(document.activeElement, elements['chat-input']);
elements['chat-close'].fire('click');
assert(!elements['chat-panel'].classList.contains('chat-open'));
assert(!elements['mobile-controls'].classList.contains('chat-active'));
assert.equal(document.activeElement, canvas);
canvas.fire('pointerdown', { pointerId: 23, pointerType: 'mouse', clientX: 650, clientY: 500 });
clock += 2_100;
canvas.fire('pointerup', { pointerId: 23, pointerType: 'mouse', clientX: 650, clientY: 500 });
assert(elements['chat-panel'].classList.contains('chat-open'), 'Long mouse press still opens chat');
assert.match(socket.sent.at(-1), /^p/);
elements['chat-close'].fire('click');
console.log('PASS client: multi-touch controls, aimed shots, cancellation and mobile chat');

const html = '<img src=x onerror="alert(1)">';
socket.message('c', { id: 2, name: '<script>Ola</script>', text: html });
let row = elements['chat-history'].children.at(-1);
assert.equal(row.children[0].textContent, '<script>Ola</script>: ');
assert.equal(row.children[1].textContent, html);
for (let index = 0; index < 60; index++) socket.message('c', { name: 'Ola', text: String(index) });
assert.equal(elements['chat-history'].children.length, 50);
socket.onmessage({ data: 'b:Ciężka miłość' });
assert.equal(elements['chat-history'].children.at(-1).textContent, 'Ciężka miłość');
key('t');
assert.equal(document.activeElement, elements['chat-input']);
const count = socket.sent.length;
key('a');
assert.equal(socket.sent.length, count, 'Typing must not move the player');
key('Escape');
assert.equal(document.activeElement, canvas);
key('d');
assert.equal(socket.sent.at(-1), 'r');
for (let index = 0; index < 5; index++) {
  clock += 700;
  elements['chat-input'].value = html;
  elements['chat-form'].fire('submit');
  assert.equal(socket.sent.at(-1), `m${html}`);
}
const afterFive = socket.sent.length;
clock += 700;
elements['chat-input'].value = 'sixth';
elements['chat-form'].fire('submit');
assert.equal(socket.sent.length, afterFive);
assert.match(elements['chat-status'].textContent, /Odczekaj/);
console.log('PASS client: chat is text-only, history is bounded, focus and cooldown work');

left.fire('pointerdown', { pointerId: 24 });
assert.equal(intervals.size, 1);
socket.disconnect();
assert.equal(intervals.size, 0, 'Disconnect stops held controls');
assert.equal(window.data, null);
assert(!elements['join-screen'].hidden);
assert.equal(elements['mobile-controls'].hidden, true);
elements['join-form'].fire('submit');
assert.equal(sockets.length, 2, 'The join form allows an explicit reconnect');
assert.equal(images, 103, 'Reconnecting must reuse all images');
console.log('PASS client: disconnect resets state and reconnect reuses assets');
