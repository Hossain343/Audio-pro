import test from 'node:test';
import assert from 'node:assert/strict';
import {
  APRO_HEADER_SIZE,
  PacketType,
  buildZipArchive,
  calculateAudioLevels,
  calculateBridgeMetrics,
  decodeAproPacket,
  encodeAproPacket,
} from './protocol';

test('APRO packet encodes and decodes payload without loss', () => {
  const payload = new Uint8Array([10, 20, 30, 40, 255]);
  const encoded = encodeAproPacket(PacketType.MicPcm, 1, 105, 512, payload);

  assert.equal(encoded.length, APRO_HEADER_SIZE + payload.length);
  const decoded = decodeAproPacket(encoded);
  assert.ok(decoded !== null);
  assert.equal(decoded.type, PacketType.MicPcm);
  assert.equal(decoded.channels, 1);
  assert.equal(decoded.sequence, 105);
  assert.equal(decoded.timestampTicks, 512);
  assert.deepEqual(Array.from(decoded.payload), Array.from(payload));
});

test('decodeAproPacket rejects invalid magic bytes', () => {
  const encoded = encodeAproPacket(PacketType.Handshake, 1, 0, 0, new Uint8Array([1, 2]));
  encoded[0] = 0x00;
  assert.equal(decodeAproPacket(encoded), null);
});

test('calculateAudioLevels handles silence and full-scale signal', () => {
  const silence = calculateAudioLevels(new Float32Array(240));
  assert.equal(silence.rms, 0);
  assert.equal(silence.peak, 0);
  assert.equal(silence.dbfs, -96);

  const square = new Float32Array(240).fill(0.5);
  const levels = calculateAudioLevels(square);
  assert.ok(Math.abs(levels.rms - 0.5) < 1e-6);
  assert.ok(Math.abs(levels.peak - 0.5) < 1e-6);
  assert.ok(levels.dbfs > -7 && levels.dbfs < -5.5);
});

test('calculateBridgeMetrics remains under 50ms latency budget over USB', () => {
  const wired = calculateBridgeMetrics({
    status: 'connected',
    jitterBufferFrames: 2,
    bluetoothScoActive: false,
  });
  assert.ok(wired.latencyMs > 0 && wired.latencyMs < 50);
  assert.equal(wired.packetsPerSecond, 200);

  const bt = calculateBridgeMetrics({
    status: 'connected',
    jitterBufferFrames: 2,
    bluetoothScoActive: true,
  });
  assert.ok(bt.latencyMs > wired.latencyMs && bt.latencyMs < 50);
});

test('buildZipArchive produces valid PKZIP local and central directory headers', () => {
  const bytes = new TextEncoder().encode('name: audio_pro\n');
  const zip = buildZipArchive([{ path: 'audio_pro/pubspec.yaml', content: bytes }]);
  assert.equal(zip[0], 0x50); // 'P'
  assert.equal(zip[1], 0x4b); // 'K'
  assert.equal(zip[2], 0x03);
  assert.equal(zip[3], 0x04);
  // End of central directory signature at tail
  const tailOffset = zip.length - 22;
  assert.equal(zip[tailOffset], 0x50);
  assert.equal(zip[tailOffset + 1], 0x4b);
  assert.equal(zip[tailOffset + 2], 0x05);
  assert.equal(zip[tailOffset + 3], 0x06);
});
