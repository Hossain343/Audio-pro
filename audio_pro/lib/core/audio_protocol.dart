import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Binary wire protocol constants for AudioPro low-latency PCM transport.
/// Header layout (16 bytes, Little-Endian):
///   [0..3]   Magic bytes: 'A','P','R','O' (0x41, 0x50, 0x52, 0x4F)
///   [4]      Protocol version: 1
///   [5]      PacketType enum index
///   [6..7]   Flags / Channel count (bit 0..3 = channels, bit 4..7 = flags)
///   [8..11]  Sequence number (uint32)
///   [12..13] Timestamp offset in 100us ticks (uint16)
///   [14..15] Payload byte length (uint16)
class AudioProtocol {
  AudioProtocol._();

  static const int magic0 = 0x41; // 'A'
  static const int magic1 = 0x50; // 'P'
  static const int magic2 = 0x52; // 'R'
  static const int magic3 = 0x4F; // 'O'
  static const int version = 1;
  static const int headerSize = 16;

  static const int defaultPort = 38900;
  static const int controlPort = 38901;
  static const int sampleRate = 48000;
  static const int frameSamples = 240; // 5 ms at 48 kHz
  static const int maxPayloadBytes = 8192;
}

enum PacketType {
  handshake,
  handshakeAck,
  micPcm,
  speakerPcm,
  heartbeat,
  deviceMeta,
}

class AudioPacket {
  const AudioPacket({
    required this.type,
    required this.channels,
    required this.sequence,
    required this.timestampTicks,
    required this.payload,
  });

  final PacketType type;
  final int channels;
  final int sequence;
  final int timestampTicks;
  final Uint8List payload;

  Uint8List encode() {
    final totalLength = AudioProtocol.headerSize + payload.length;
    final bytes = Uint8List(totalLength);
    final bd = ByteData.sublistView(bytes);

    bytes[0] = AudioProtocol.magic0;
    bytes[1] = AudioProtocol.magic1;
    bytes[2] = AudioProtocol.magic2;
    bytes[3] = AudioProtocol.magic3;
    bytes[4] = AudioProtocol.version;
    bytes[5] = type.index;
    bytes[6] = channels & 0x0F;
    bytes[7] = 0;
    bd.setUint32(8, sequence, Endian.little);
    bd.setUint16(12, timestampTicks & 0xFFFF, Endian.little);
    bd.setUint16(14, payload.length, Endian.little);

    if (payload.isNotEmpty) {
      bytes.setRange(AudioProtocol.headerSize, totalLength, payload);
    }
    return bytes;
  }

  static AudioPacket? tryDecode(Uint8List frame) {
    if (frame.length < AudioProtocol.headerSize) return null;
    if (frame[0] != AudioProtocol.magic0 ||
        frame[1] != AudioProtocol.magic1 ||
        frame[2] != AudioProtocol.magic2 ||
        frame[3] != AudioProtocol.magic3) {
      return null;
    }
    if (frame[4] != AudioProtocol.version) return null;

    final typeIndex = frame[5];
    if (typeIndex < 0 || typeIndex >= PacketType.values.length) return null;

    final bd = ByteData.sublistView(frame);
    final payloadLength = bd.getUint16(14, Endian.little);
    if (payloadLength > AudioProtocol.maxPayloadBytes ||
        frame.length < AudioProtocol.headerSize + payloadLength) {
      return null;
    }

    final channels = frame[6] & 0x0F;
    final sequence = bd.getUint32(8, Endian.little);
    final timestampTicks = bd.getUint16(12, Endian.little);
    final payload = Uint8List.fromList(
      frame.sublist(
        AudioProtocol.headerSize,
        AudioProtocol.headerSize + payloadLength,
      ),
    );

    return AudioPacket(
      type: PacketType.values[typeIndex],
      channels: channels == 0 ? 1 : channels,
      sequence: sequence,
      timestampTicks: timestampTicks,
      payload: payload,
    );
  }

  static AudioPacket handshake({
    required String deviceName,
    required String platform,
    int sampleRate = AudioProtocol.sampleRate,
  }) {
    final jsonBytes = utf8.encode(
      jsonEncode(<String, dynamic>{
        'deviceName': deviceName,
        'platform': platform,
        'sampleRate': sampleRate,
        'frameSamples': AudioProtocol.frameSamples,
      }),
    );
    return AudioPacket(
      type: PacketType.handshake,
      channels: 1,
      sequence: 0,
      timestampTicks: 0,
      payload: Uint8List.fromList(jsonBytes),
    );
  }
}

/// Lock-free style single-producer/single-consumer PCM jitter ring buffer.
class PcmRingBuffer {
  PcmRingBuffer(this.capacityBytes) : _buffer = Uint8List(capacityBytes);

  final int capacityBytes;
  final Uint8List _buffer;
  int _readIdx = 0;
  int _writeIdx = 0;
  int _available = 0;

  int get availableBytes => _available;
  int get freeBytes => capacityBytes - _available;

  int write(Uint8List data) {
    final toWrite = math.min(data.length, freeBytes);
    for (int i = 0; i < toWrite; i++) {
      _buffer[_writeIdx] = data[i];
      _writeIdx = (_writeIdx + 1) % capacityBytes;
    }
    _available += toWrite;
    return toWrite;
  }

  Uint8List read(int count) {
    final toRead = math.min(count, _available);
    final out = Uint8List(count);
    for (int i = 0; i < toRead; i++) {
      out[i] = _buffer[_readIdx];
      _readIdx = (_readIdx + 1) % capacityBytes;
    }
    _available -= toRead;
    return out;
  }

  void clear() {
    _readIdx = 0;
    _writeIdx = 0;
    _available = 0;
  }
}

/// Computes normalized RMS [0..1] and Peak [0..1] from 16-bit Little-Endian PCM.
({double rms, double peak, double dbfs}) computePcmLevels(Uint8List pcm16Le) {
  final sampleCount = pcm16Le.length ~/ 2;
  if (sampleCount == 0) {
    return (rms: 0.0, peak: 0.0, dbfs: -96.0);
  }
  final bd = ByteData.sublistView(pcm16Le);
  double sumSquares = 0.0;
  double maxPeak = 0.0;

  for (int i = 0; i < sampleCount; i++) {
    final sample = bd.getInt16(i * 2, Endian.little) / 32768.0;
    final absVal = sample.abs();
    if (absVal > maxPeak) maxPeak = absVal;
    sumSquares += sample * sample;
  }

  final rms = math.sqrt(sumSquares / sampleCount).clamp(0.0, 1.0);
  final dbfs = rms <= 1e-5 ? -96.0 : (20.0 * math.log(rms) / math.ln10);
  return (rms: rms, peak: maxPeak.clamp(0.0, 1.0), dbfs: dbfs);
}
