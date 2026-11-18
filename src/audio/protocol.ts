export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected';

export type AudioEndpointType =
  | 'builtInMic'
  | 'bluetoothSco'
  | 'wiredHeadset'
  | 'usbAudio'
  | 'speakerphone'
  | 'earpiece'
  | 'bluetoothA2dp'
  | 'virtualDriver';

export interface AudioEndpoint {
  id: string;
  name: string;
  type: AudioEndpointType;
  isInput: boolean;
  isDefault?: boolean;
}

export interface BridgeMetrics {
  latencyMs: number;
  jitterMs: number;
  packetsPerSecond: number;
  packetLossPct: number;
  sampleRateHz: number;
  frameDurationMs: number;
}

export const APRO_MAGIC = [0x41, 0x50, 0x52, 0x4f] as const;
export const APRO_VERSION = 1;
export const APRO_HEADER_SIZE = 16;

export const PacketType = {
  Handshake: 0,
  HandshakeAck: 1,
  MicPcm: 2,
  SpeakerPcm: 3,
  Heartbeat: 4,
  DeviceMeta: 5,
} as const;

export type PacketTypeValue = (typeof PacketType)[keyof typeof PacketType];

export interface DecodedPacket {
  type: PacketTypeValue;
  channels: number;
  sequence: number;
  timestampTicks: number;
  payload: Uint8Array;
}

export function encodeAproPacket(
  type: PacketTypeValue,
  channels: number,
  sequence: number,
  timestampTicks: number,
  payload: Uint8Array
): Uint8Array {
  const out = new Uint8Array(APRO_HEADER_SIZE + payload.length);
  const view = new DataView(out.buffer);
  out[0] = APRO_MAGIC[0];
  out[1] = APRO_MAGIC[1];
  out[2] = APRO_MAGIC[2];
  out[3] = APRO_MAGIC[3];
  out[4] = APRO_VERSION;
  out[5] = type;
  out[6] = channels & 0x0f;
  out[7] = 0;
  view.setUint32(8, sequence >>> 0, true);
  view.setUint16(12, timestampTicks & 0xffff, true);
  view.setUint16(14, payload.length & 0xffff, true);
  if (payload.length > 0) {
    out.set(payload, APRO_HEADER_SIZE);
  }
  return out;
}

export function decodeAproPacket(frame: Uint8Array): DecodedPacket | null {
  if (frame.length < APRO_HEADER_SIZE) return null;
  if (
    frame[0] !== APRO_MAGIC[0] ||
    frame[1] !== APRO_MAGIC[1] ||
    frame[2] !== APRO_MAGIC[2] ||
    frame[3] !== APRO_MAGIC[3]
  ) {
    return null;
  }
  if (frame[4] !== APRO_VERSION) return null;

  const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
  const payloadLength = view.getUint16(14, true);
  if (frame.length < APRO_HEADER_SIZE + payloadLength) return null;

  return {
    type: frame[5] as PacketTypeValue,
    channels: Math.max(1, frame[6] & 0x0f),
    sequence: view.getUint32(8, true),
    timestampTicks: view.getUint16(12, true),
    payload: frame.slice(APRO_HEADER_SIZE, APRO_HEADER_SIZE + payloadLength),
  };
}

export function calculateAudioLevels(samples: Float32Array): {
  rms: number;
  peak: number;
  dbfs: number;
} {
  if (samples.length === 0) {
    return { rms: 0, peak: 0, dbfs: -96 };
  }
  let sumSq = 0;
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const absVal = Math.abs(samples[i]);
    if (absVal > peak) peak = absVal;
    sumSq += samples[i] * samples[i];
  }
  const rms = Math.min(1, Math.max(0, Math.sqrt(sumSq / samples.length)));
  const clampedPeak = Math.min(1, Math.max(0, peak));
  const dbfs = rms <= 1e-5 ? -96 : 20 * Math.log10(rms);
  return { rms, peak: clampedPeak, dbfs };
}

export function calculateBridgeMetrics(params: {
  status: ConnectionStatus;
  jitterBufferFrames: number;
  bluetoothScoActive: boolean;
  frameDurationMs?: number;
}): BridgeMetrics {
  const frameDurationMs = params.frameDurationMs ?? 5;
  if (params.status !== 'connected') {
    return {
      latencyMs: 0,
      jitterMs: 0,
      packetsPerSecond: 0,
      packetLossPct: 0,
      sampleRateHz: 48000,
      frameDurationMs,
    };
  }
  const usbSocketMs = 2.4;
  const mobileIoMs = params.bluetoothScoActive ? 16.5 : 8.5;
  const hostWasapiMs = 6.2;
  const jitterMs = Number((params.jitterBufferFrames * frameDurationMs).toFixed(1));
  const latencyMs = Number(
    (usbSocketMs + mobileIoMs + hostWasapiMs + jitterMs).toFixed(1)
  );
  return {
    latencyMs,
    jitterMs,
    packetsPerSecond: Math.round(1000 / frameDurationMs),
    packetLossPct: 0.0,
    sampleRateHz: 48000,
    frameDurationMs,
  };
}

export interface ZipEntryInput {
  path: string;
  content: Uint8Array;
}

const CRC32_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(data: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < data.length; i++) {
    c = CRC32_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

/**
 * Builds an uncompressed (STORE method 0) PKZIP archive in memory with valid CRC32.
 */
export function buildZipArchive(entries: ZipEntryInput[]): Uint8Array {
  const encoder = new TextEncoder();
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBytes = encoder.encode(entry.path.replace(/^\/+/, ''));
    const data = entry.content;
    const sum = crc32(data);

    const localHeader = new Uint8Array(30 + nameBytes.length);
    const lv = new DataView(localHeader.buffer);
    lv.setUint32(0, 0x04034b50, true);
    lv.setUint16(4, 20, true);
    lv.setUint16(6, 0x0800, true); // UTF-8
    lv.setUint16(8, 0, true); // STORE
    lv.setUint16(10, 0, true);
    lv.setUint16(12, 0, true);
    lv.setUint32(14, sum, true);
    lv.setUint32(18, data.length, true);
    lv.setUint32(22, data.length, true);
    lv.setUint16(26, nameBytes.length, true);
    lv.setUint16(28, 0, true);
    localHeader.set(nameBytes, 30);

    localParts.push(localHeader, data);

    const centralHeader = new Uint8Array(46 + nameBytes.length);
    const cv = new DataView(centralHeader.buffer);
    cv.setUint32(0, 0x02014b50, true);
    cv.setUint16(4, 20, true);
    cv.setUint16(6, 20, true);
    cv.setUint16(8, 0x0800, true);
    cv.setUint16(10, 0, true);
    cv.setUint16(12, 0, true);
    cv.setUint16(14, 0, true);
    cv.setUint32(16, sum, true);
    cv.setUint32(20, data.length, true);
    cv.setUint32(24, data.length, true);
    cv.setUint16(28, nameBytes.length, true);
    cv.setUint16(30, 0, true);
    cv.setUint16(32, 0, true);
    cv.setUint16(34, 0, true);
    cv.setUint16(36, 0, true);
    cv.setUint32(38, 0, true);
    cv.setUint32(42, offset, true);
    centralHeader.set(nameBytes, 46);

    centralParts.push(centralHeader);
    offset += localHeader.length + data.length;
  }

  const centralSize = centralParts.reduce((acc, p) => acc + p.length, 0);
  const eocd = new Uint8Array(22);
  const ev = new DataView(eocd.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(4, 0, true);
  ev.setUint16(6, 0, true);
  ev.setUint16(8, entries.length, true);
  ev.setUint16(10, entries.length, true);
  ev.setUint32(12, centralSize, true);
  ev.setUint32(16, offset, true);
  ev.setUint16(20, 0, true);

  const totalSize = offset + centralSize + eocd.length;
  const archive = new Uint8Array(totalSize);
  let cursor = 0;
  for (const p of localParts) {
    archive.set(p, cursor);
    cursor += p.length;
  }
  for (const p of centralParts) {
    archive.set(p, cursor);
    cursor += p.length;
  }
  archive.set(eocd, cursor);
  return archive;
}
