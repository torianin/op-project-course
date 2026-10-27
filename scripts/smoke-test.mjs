import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { GameClient, get } from '../test/ws-client.mjs';

const base = new URL(process.argv[2] || 'http://127.0.0.1:8080');
const clients = [];
try {
  assert.equal((await (await get(base, '/healthz')).json()).status, 'ok');
  assert.match(await (await get(base, '/')).text(), /Fat Angel Multiplayer/);
  assert.match(await (await get(base, '/application.js')).text(), /WebSocket/);
  assert((await (await get(base, '/img/czerwony/0.png')).arrayBuffer()).byteLength > 0);

  const first = await GameClient.connect(base);
  clients.push(first);
  const second = await GameClient.connect(base);
  clients.push(second);
  const suffix = Date.now().toString(36);
  const firstName = `SmokeA-${suffix}`;
  const secondName = `SmokeB-${suffix}`;
  const firstIdentity = await first.join(firstName);
  const secondIdentity = await second.join(secondName);
  assert.notEqual(firstIdentity.id, secondIdentity.id);
  assert.equal(firstIdentity.name, firstName);
  assert.equal(secondIdentity.name, secondName);

  const initial = await first.snapshot();
  assert(initial.id.includes(firstIdentity.id) && initial.id.includes(secondIdentity.id));
  assert.equal(initial.name[initial.id.indexOf(firstIdentity.id)], firstName);
  assert.equal(initial.name[initial.id.indexOf(secondIdentity.id)], secondName);

  // With no subscription and no polling, the simulation must still advance.
  const initialX = initial.coordinates[initial.id.indexOf(firstIdentity.id)][0];
  first.socket.send('r');
  await delay(400);
  const idle = await first.snapshot();
  assert(idle.tick - initial.tick >= 12, 'Simulation must advance without snapshot requests');
  assert(idle.coordinates[idle.id.indexOf(firstIdentity.id)][0] > initialX + 3, 'Movement must advance without polling');

  // Read-only requests must not accelerate the authoritative clock.
  const beforePolling = performance.now();
  let polled = idle;
  for (let index = 0; index < 10; index++) {
    await delay(40);
    polled = await first.snapshot();
  }
  const elapsed = performance.now() - beforePolling;
  const tickDelta = polled.tick - idle.tick;
  assert(tickDelta >= elapsed * 0.04 && tickDelta <= elapsed * 0.08 + 6,
    `Polling must preserve a roughly 60 Hz clock: ${tickDelta} ticks / ${elapsed.toFixed(0)} ms`);

  await first.subscribe();
  await second.subscribe();
  const pushedAfter = first.sequence;
  const pushStarted = performance.now();
  await delay(1_200);
  const pushes = first.packets.filter(packet => packet.type === 'j' && packet.sequence > pushedAfter);
  const pushElapsed = performance.now() - pushStarted;
  assert(pushes.length >= 12 && pushes.length <= 36,
    `Subscribed state should arrive near 20 Hz without polling: ${pushes.length} / ${pushElapsed.toFixed(0)} ms`);
  assert(pushes.at(-1).value.tick > pushes[0].value.tick);

  const shotState = first.waitFor(packet => packet.type === 'j' && packet.value.bullets.length > 0);
  first.socket.send('p9999.5,-9999.5');
  const shot = (await shotState).value;
  assert(shot.bullets.every(point => point.every(Number.isFinite)));

  const text = `smoke-${suffix}`;
  const echoes = [first, second].map(client => client.waitFor(packet => packet.type === 'c' && packet.value.text === text));
  first.socket.send(`m${text}`);
  for (const packet of await Promise.all(echoes)) assert.deepEqual(packet.value, { id: firstIdentity.id, name: firstName, text });

  const departure = first.waitFor(packet => packet.type === 'j' && !packet.value.id.includes(secondIdentity.id), { timeout: 15_000 });
  await second.close();
  await departure;
  console.log(`PASS ${base.origin}: HTTP, assets, joined identities, independent 60 Hz simulation, pushed state, shots, structured chat, disconnect`);
} finally {
  await Promise.all(clients.map(client => client.close()));
}
