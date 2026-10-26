import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

const base = new URL(process.argv[2] || 'http://127.0.0.1:8080');
const socketURL = new URL('/ws', base);
socketURL.protocol = base.protocol === 'https:' ? 'wss:' : 'ws:';

async function get(path) {
  const response = await fetch(new URL(path, base), { signal: AbortSignal.timeout(30_000) });
  assert.equal(response.status, 200, `${path} must return HTTP 200`);
  return response;
}

async function connect() {
  const socket = new WebSocket(socketURL);
  const inbox = [];
  const waiters = [];
  socket.addEventListener('message', ({ data }) => {
    const index = waiters.findIndex(({ predicate }) => predicate(data));
    if (index < 0) inbox.push(data);
    else waiters.splice(index, 1)[0].resolve(data);
  });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('WebSocket opening timed out')), 10_000);
    socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
    socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('WebSocket opening failed')); }, { once: true });
  });
  function receive(predicate) {
    const index = inbox.findIndex(predicate);
    if (index >= 0) return Promise.resolve(inbox.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve: value => { clearTimeout(timeout); resolve(value); } };
      const timeout = setTimeout(() => {
        waiters.splice(waiters.indexOf(waiter), 1);
        reject(new Error('Expected WebSocket message did not arrive'));
      }, 5_000);
      waiters.push(waiter);
    });
  }
  return {
    socket,
    receive,
    async request(message, prefix) {
      const response = receive(data => data.startsWith(prefix));
      socket.send(message);
      return response;
    },
    async state() {
      const data = await this.request('j', 'j:');
      assert(!data.includes('NaN') && !data.includes('Infinity'), 'State must contain finite coordinates');
      return JSON.parse(data.slice(2));
    },
    async close() {
      if (socket.readyState === WebSocket.CLOSED) return;
      await new Promise(resolve => {
        const timeout = setTimeout(resolve, 2_000);
        socket.addEventListener('close', () => { clearTimeout(timeout); resolve(); }, { once: true });
        socket.close();
      });
    },
  };
}

const clients = [];
try {
  assert.equal((await (await get('/healthz')).json()).status, 'ok');
  assert.match(await (await get('/')).text(), /Fat Angel Multiplayer/);
  assert.match(await (await get('/application.js')).text(), /WebSocket/);
  assert((await (await get('/img/czerwony/0.png')).arrayBuffer()).byteLength > 0);
  const [first, second] = await Promise.all([connect(), connect()]);
  clients.push(first, second);
  const firstID = Number((await first.request('i', 'i:')).slice(2));
  const secondID = Number((await second.request('i', 'i:')).slice(2));
  assert(Number.isSafeInteger(firstID) && firstID > 0);
  assert(Number.isSafeInteger(secondID) && secondID > 0);
  assert.notEqual(firstID, secondID);
  const suffix = Date.now().toString(36);
  const firstName = `SmokeA-${suffix}`;
  const secondName = `SmokeB-${suffix}`;
  first.socket.send(`n${firstName}`);
  second.socket.send(`n${secondName}`);
  const secondState = await second.state();
  assert(secondState.id.includes(firstID) && secondState.id.includes(secondID));
  const initial = await first.state();
  assert.equal(initial.name[initial.id.indexOf(firstID)], firstName);
  assert.equal(initial.name[initial.id.indexOf(secondID)], secondName);

  const initialX = initial.coordinates[initial.id.indexOf(firstID)][0];
  first.socket.send('r');
  await delay(40);
  const moved = await first.state();
  assert(moved.coordinates[moved.id.indexOf(firstID)][0] > initialX, 'Movement must update player coordinates');
  first.socket.send('p9999.5,-9999.5');
  const shot = await first.state();
  assert(shot.bullets.length > 0, 'Fractional aim coordinates must produce a bullet');
  const coordinates = shot.coordinates[shot.id.indexOf(firstID)];
  first.socket.send(`p${coordinates[0]},${coordinates[1]}`);
  const zeroDistanceShot = await first.state();
  assert(zeroDistanceShot.bullets.every(point => point.every(Number.isFinite)));

  const message = `${firstName}: smoke-${suffix}`;
  const echoes = [first.receive(data => data === message), second.receive(data => data === message)];
  first.socket.send(`msmoke-${suffix}`);
  assert.deepEqual(await Promise.all(echoes), [message, message]);
  await second.close();
  let remaining;
  for (let attempt = 0; attempt < 10; attempt++) {
    remaining = await first.state();
    if (!remaining.id.includes(secondID)) break;
    await delay(50);
  }
  assert(!remaining.id.includes(secondID), 'Disconnected player must leave the room');
  console.log(`PASS ${base.origin}: HTTP, assets, two players, names, movement, shots, chat, disconnect`);
} finally {
  await Promise.all(clients.map(client => client.close()));
}
