import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_pro/core/audio_protocol.dart';

void main() {
  group('AudioProtocol binary framing', () {
    test('round-trips PCM packet cleanly', () {
      final payload = Uint8List.fromList(List<int>.generate(480, (i) => i & 0xFF));
      final packet = AudioPacket(
        type: PacketType.micPcm,
        channels: 1,
        sequence: 42,
        timestampTicks: 1234,
        payload: payload,
      );

      final encoded = packet.encode();
      expect(encoded.length, AudioProtocol.headerSize + 480);

      final decoded = AudioPacket.tryDecode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.type, PacketType.micPcm);
      expect(decoded.channels, 1);
      expect(decoded.sequence, 42);
      expect(decoded.timestampTicks, 1234);
      expect(decoded.payload, payload);
    });

    test('rejects corrupted magic header', () {
      final packet = AudioPacket.handshake(
        deviceName: 'Pixel-9-Pro',
        platform: 'Android',
      ).encode();
      packet[0] = 0x00;
      expect(AudioPacket.tryDecode(packet), isNull);
    });
  });

  group('PcmRingBuffer', () {
    test('handles wrap-around reads and writes accurately', () {
      final ring = PcmRingBuffer(8);
      expect(ring.write(Uint8List.fromList([1, 2, 3, 4, 5])), 5);
      expect(ring.availableBytes, 5);

      final first = ring.read(3);
      expect(first, Uint8List.fromList([1, 2, 3]));
      expect(ring.availableBytes, 2);

      expect(ring.write(Uint8List.fromList([6, 7, 8, 9])), 4);
      expect(ring.availableBytes, 6);

      final second = ring.read(6);
      expect(second, Uint8List.fromList([4, 5, 6, 7, 8, 9]));
      expect(ring.availableBytes, 0);
    });
  });

  group('computePcmLevels', () {
    test('returns silence floor for zero buffer', () {
      final levels = computePcmLevels(Uint8List(480));
      expect(levels.rms, 0.0);
      expect(levels.peak, 0.0);
      expect(levels.dbfs, -96.0);
    });
  });
}
