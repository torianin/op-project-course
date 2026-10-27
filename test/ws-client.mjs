import assert from 'node:assert/strict';

export class GameClient {
  constructor(url) {
    const target = new URL('/ws', url);
    target.protocol = target.protocol === 'https:' ? 'wss:' : 'ws:';
    this.socket = new WebSocket(target);
    this.sequence = 0;
    this.packets = [];
    this.waiters = new Set();
    this.closed = null;
    this.socket.addEventListener('message', ({ data }) => {
      const text = String(data);
      const type = text.slice(0, 1);
      let value = text.slice(2);
      if (['a', 'c', 'e', 'j'].includes(type)) value = JSON.parse(value);
      const packet = { type, value, text, sequence: ++this.sequence, at: performance.now() };
      if (type === 'j') this.latestState = packet;
      this.packets.push(packet);
      if (this.packets.length > 300) this.packets.shift();
      for (const waiter of this.waiters) {
        if (packet.sequence > waiter.after && waiter.predicate(packet)) waiter.resolve(packet);
      }
    });
    this.socket.addEventListener('close', event => {
      this.closed = { code: event.code, reason: event.reason, wasClean: event.wasClean };
    });
  }

  static async connect(url) {
    const client = new GameClient(url);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WebSocket open timed out')), 10_000);
      client.socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
      client.socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('WebSocket open failed')); }, { once: true });
    });
    return client;
  }

  waitFor(predicate, { after = this.sequence, timeout = 5_000 } = {}) {
    const existing = this.packets.find(packet => packet.sequence > after && predicate(packet));
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const waiter = {
        after,
        predicate,
        resolve: packet => {
          clearTimeout(timer);
          this.waiters.delete(waiter);
          resolve(packet);
        },
      };
      const timer = setTimeout(() => {
        this.waiters.delete(waiter);
        reject(new Error('Expected WebSocket packet timed out'));
      }, timeout);
      this.waiters.add(waiter);
    });
  }

  async request(message, predicate) {
    const response = this.waitFor(predicate);
    this.socket.send(message);
    return response;
  }

  async join(name) {
    const packet = await this.request(`n${name}`, packet => ['a', 'e'].includes(packet.type));
    assert.equal(packet.type, 'a', `Nickname rejected: ${JSON.stringify(packet.value)}`);
    assert(Number.isSafeInteger(packet.value.id) && packet.value.id > 0);
    this.identity = packet.value;
    return packet.value;
  }

  async snapshot() {
    const packet = await this.request('j', packet => ['j', 'e'].includes(packet.type));
    assert.equal(packet.type, 'j', `Snapshot rejected: ${JSON.stringify(packet.value)}`);
    assert(Number.isSafeInteger(packet.value.tick), 'Snapshot must identify the authoritative simulation tick');
    assert(!packet.text.includes('NaN') && !packet.text.includes('Infinity'));
    return packet.value;
  }

  async subscribe() {
    const packet = await this.request('s', packet => ['j', 'e'].includes(packet.type));
    assert.equal(packet.type, 'j', `Subscription rejected: ${JSON.stringify(packet.value)}`);
    return packet.value;
  }

  async waitUntilClosed(timeout = 5_000) {
    if (this.closed) return this.closed;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('WebSocket close timed out')), timeout);
      this.socket.addEventListener('close', () => {
        clearTimeout(timer);
        resolve(this.closed);
      }, { once: true });
    });
  }

  async close() {
    if (this.socket.readyState === WebSocket.CLOSED) return;
    this.socket.close();
    await this.waitUntilClosed(3_000).catch(() => {});
  }
}

export async function get(base, path) {
  const response = await fetch(new URL(path, base), { signal: AbortSignal.timeout(30_000) });
  assert.equal(response.status, 200, `${path} must return HTTP 200`);
  return response;
}
