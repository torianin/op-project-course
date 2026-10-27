import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { GameClient, get } from '../test/ws-client.mjs';
import { rawWebSocket } from '../test/raw-websocket.mjs';

const base = new URL(process.argv[2] || 'http://127.0.0.1:8080');
const clients = [];
const suffix = Date.now().toString(36);
async function connect() {
  const client = await GameClient.connect(base);
  clients.push(client);
  return client;
}
async function errorFor(client, message, code) {
  const packet = await client.request(message, packet => ['a', 'c', 'e', 'j'].includes(packet.type));
  assert.equal(packet.type, 'e', `Rejected input must not produce an accepted packet: ${JSON.stringify(packet)}`);
  assert.equal(packet.value.code, code);
  assert.equal(typeof packet.value.message, 'string');
  assert.equal(client.socket.readyState, WebSocket.OPEN, 'Validation errors must leave the socket open');
  await delay(120); // Keep validation-error checks below the error-response bucket limit.
}
async function chat(sender, recipient, name, input, expected = input.normalize('NFC').trim()) {
  const received = recipient.waitFor(packet => packet.type === 'c');
  sender.socket.send(`m${input}`);
  const packet = await received;
  assert.deepEqual(packet.value, { id: sender.identity.id, name, text: expected });
}

try {
  const health = await get(base, '/healthz');
  assert.equal((await health.json()).status, 'ok');
  assert.equal(health.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(health.headers.get('x-frame-options'), 'DENY');
  const csp = health.headers.get('content-security-policy');
  assert(csp.includes("script-src 'self'") && csp.includes("frame-ancestors 'none'"));
  assert(!csp.includes('unsafe-inline') && !csp.includes('unsafe-eval'));
  assert.equal((await rawWebSocket(base, { origin: base.origin })).status, 101, 'Same-origin upgrade must succeed');
  const wrongPort = new URL(base);
  wrongPort.port = String(Number(base.port || (base.protocol === 'https:' ? 443 : 80)) + 1);
  const wrongScheme = new URL(base);
  wrongScheme.protocol = base.protocol === 'https:' ? 'http:' : 'https:';
  for (const origin of ['null', 'https://attacker.invalid', wrongPort.origin, wrongScheme.origin]) {
    assert.equal((await rawWebSocket(base, { origin })).status, 403, `Reject Origin ${origin}`);
  }
  console.log('PASS Origin: full scheme, host, port; null and foreign origins rejected');

  const first = await connect(); // The anonymous CLI handshake intentionally has no Origin.
  const second = await connect();
  const third = await connect();
  const secondName = `GuardB-${suffix}`;
  const thirdName = '😀'.repeat(30);
  const secondIdentity = await second.join(secondName);
  const thirdIdentity = await third.join(thirdName);
  assert.equal(thirdIdentity.name, thirdName, 'Nickname length is measured in Unicode code points');
  const unjoinedID = Number((await first.request('i', packet => packet.type === 'i')).value);
  assert(!((await second.snapshot()).id.includes(unjoinedID)), 'Unnamed sessions must not appear in the game');
  for (const message of ['mshould-not-appear', 'r', 's', 'j']) await errorFor(first, message, 'not_joined');
  for (const name of ['', ' ', 'x', 'a'.repeat(31), '😀'.repeat(31), 'ab\0', 'ab\u0085', 'ab\u202e', 'ab\u2066', 'ab\n']) {
    await errorFor(first, `n${name}`, 'invalid_name');
    await delay(2_050); // Refill the name-attempt bucket, including invalid attempts.
  }
  const canonicalName = 'éx';
  const firstIdentity = await first.join('  e\u0301x  ');
  assert.equal(firstIdentity.name, canonicalName);
  assert.equal((await first.join(canonicalName)).id, firstIdentity.id, 'An identical name acknowledgement is idempotent');
  await errorFor(first, `nDifferent-${suffix}`, 'name_locked');
  const duplicate = await connect();
  await errorFor(duplicate, `n${secondName.toUpperCase()}`, 'name_taken');
  await duplicate.close();
  console.log('PASS join: required, canonical NFC names, 2–30 code points, controls/bidi rejected, identity locked, duplicate names rejected');

  // Invalid attempts consume the same chat budget as accepted messages.
  const invalidByClient = [
    [first, ['', '   ', '\n', 'ab\0', 'ab\u0085']],
    [second, ['a'.repeat(501), '😀'.repeat(501), 'ab\u202e', 'ab\u2066', 'ab\r\n']],
  ];
  for (const [client, invalidTexts] of invalidByClient) {
    for (const text of invalidTexts) await errorFor(client, `m${text}`, 'invalid_chat');
  }
  assert(!third.packets.some(packet => packet.type === 'c'), 'Invalid chat must never reach another player');
  console.log('PASS chat validation: lengths, controls, newlines and bidi; invalid messages are not broadcast');
  await delay(10_300);

  await chat(first, third, canonicalName, '<img src=x onerror="alert(1)">&"');
  await chat(first, third, canonicalName, `${secondName}: forged sender`);
  await chat(first, third, canonicalName, '  e\u0301  ', 'é');
  await chat(first, third, canonicalName, 'x');
  await chat(first, third, canonicalName, '😀'.repeat(500));
  await errorFor(first, 'mblocked-sixth-message', 'rate_limited');
  console.log('PASS structured chat: raw HTML preserved as text, sender server-owned, NFC, 1/500 code-point boundaries, per-socket burst/refill limit');
  await delay(10_300);

  for (let index = 0; index < 5; index++) await chat(first, third, canonicalName, `IP-A-${index}`);
  for (let index = 0; index < 5; index++) await chat(second, third, secondName, `IP-B-${index}`);
  await errorFor(third, 'mblocked-by-IP-budget', 'rate_limited');
  console.log('PASS shared IP chat budget: burst of 10 across different sockets');

  const binary = await connect();
  const binaryClose = binary.waitUntilClosed();
  binary.socket.send(new Uint8Array([0x61, 0x62]));
  assert.equal((await binaryClose).code, 4003, 'Binary messages must close with the bad-type policy code');
  const oversized = await connect();
  await errorFor(oversized, `n${'x'.repeat(4095)}`, 'invalid_name'); // Exactly 4096 bytes reaches application validation.
  const oversizedClose = oversized.waitUntilClosed();
  oversized.socket.send(`m${'x'.repeat(4096)}`);
  assert.equal((await oversizedClose).code, 1009, 'Frames over 4096 bytes must be rejected by the frame-size limit');
  const invalidUTF8 = await rawWebSocket(base, { invalidText: Buffer.from([0xc3, 0x28]) });
  assert.equal(invalidUTF8.status, 101);
  assert([1007, 4003].includes(invalidUTF8.closeCode), `Invalid UTF-8 must be rejected, got ${invalidUTF8.closeCode}`);
  console.log('PASS wire protocol: binary, oversized frames and invalid UTF-8 rejected');

  const flood = await connect();
  const floodClose = flood.waitUntilClosed();
  for (let index = 0; index < 240; index++) flood.socket.send('i');
  assert.equal((await floodClose).code, 4009, 'General message floods must close with the rate-limit policy code');
  assert.equal((await (await get(base, '/healthz')).json()).status, 'ok');
  console.log(`PASS ${base.origin}: general message flood rejected, server remains healthy`);
} finally {
  await Promise.all(clients.map(client => client.close()));
}
