import http from 'node:http';
import https from 'node:https';
import { randomBytes } from 'node:crypto';

function maskedFrame(opcode, payload) {
  const mask = randomBytes(4);
  const header = Buffer.alloc(payload.length < 126 ? 2 : 4);
  header[0] = 0x80 | opcode;
  header[1] = 0x80 | (payload.length < 126 ? payload.length : 126);
  if (payload.length >= 126) header.writeUInt16BE(payload.length, 2);
  const body = Buffer.from(payload);
  for (let index = 0; index < body.length; index++) body[index] ^= mask[index % 4];
  return Buffer.concat([header, mask, body]);
}

// Raw HTTP upgrade permits Origin checks and invalid UTF-8 text frames without dependencies.
export function rawWebSocket(base, { origin, invalidText } = {}) {
  const target = new URL('/ws', base);
  const transport = target.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    const headers = {
      Connection: 'Upgrade',
      Upgrade: 'websocket',
      'Sec-WebSocket-Version': '13',
      'Sec-WebSocket-Key': randomBytes(16).toString('base64'),
    };
    if (origin !== undefined) headers.Origin = origin;
    const request = transport.request(target, { headers });
    let upgradedSocket;
    const timer = setTimeout(() => {
      request.destroy();
      upgradedSocket?.destroy();
      reject(new Error('Raw WebSocket handshake timed out'));
    }, 5_000);
    const finish = value => {
      clearTimeout(timer);
      upgradedSocket?.destroy();
      resolve(value);
    };
    request.on('response', response => {
      response.resume();
      response.on('end', () => finish({ status: response.statusCode }));
    });
    request.on('error', error => { clearTimeout(timer); reject(error); });
    request.on('upgrade', (response, socket, head) => {
      upgradedSocket = socket;
      if (!invalidText) {
        const payload = Buffer.alloc(2);
        payload.writeUInt16BE(1000);
        socket.write(maskedFrame(8, payload), () => finish({ status: response.statusCode }));
        return;
      }
      let buffered = head;
      const parse = chunk => {
        buffered = Buffer.concat([buffered, chunk]);
        while (buffered.length >= 2) {
          let length = buffered[1] & 0x7f;
          let offset = 2;
          if (length === 126) {
            if (buffered.length < 4) return;
            length = buffered.readUInt16BE(2);
            offset = 4;
          } else if (length === 127) {
            reject(new Error('Unexpected large frame during UTF-8 test'));
            finish({ status: response.statusCode });
            return;
          }
          if (buffered.length < offset + length) return;
          const opcode = buffered[0] & 0x0f;
          const payload = buffered.subarray(offset, offset + length);
          buffered = buffered.subarray(offset + length);
          if (opcode === 8) {
            const closeCode = payload.length >= 2 ? payload.readUInt16BE() : 1005;
            socket.write(maskedFrame(8, payload), () => finish({ status: response.statusCode, closeCode }));
            return;
          }
          if (opcode === 9) socket.write(maskedFrame(10, payload));
        }
      };
      socket.on('data', parse);
      socket.on('error', error => { clearTimeout(timer); reject(error); });
      socket.write(maskedFrame(1, invalidText));
      parse(Buffer.alloc(0));
    });
    request.end();
  });
}
