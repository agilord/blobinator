import 'dart:typed_data';

import 'package:blobinator/src/hybrid_blobinator.dart';
import 'package:test/test.dart';

void main() {
  late HybridBlobinator blobinator;

  setUp(() {
    blobinator = HybridBlobinator();
  });

  tearDown(() async {
    await blobinator.close();
  });

  group('HybridBlobinator Basic Operations', () {
    test('should store and retrieve blob from memory', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      final updated = await blobinator.updateBlob(key, bytes);
      expect(updated, isTrue);

      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should return null for non-existent blob', () async {
      final result = await blobinator.getBlob([1, 2, 3]);
      expect(result, isNull);
    });

    test('should delete blob from both memory and disk', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await blobinator.updateBlob(key, bytes);
      final result = await blobinator.deleteBlob(key);

      expect(result, isTrue);
      expect(await blobinator.getBlob(key), isNull);
    });

    test('should get statistics from both stores', () async {
      final key1 = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final key2 = [7, 8, 9];
      final bytes2 = [10, 11, 12];

      await blobinator.updateBlob(key1, bytes1);
      await blobinator.updateBlob(key2, bytes2);

      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(2));
      expect(stats.totalKeysSize, equals(6)); // 3 + 3
      expect(stats.totalValuesSize, equals(6)); // 3 + 3
    });
  });

  group('HybridBlobinator Migration', () {
    test('should start and stop cleanup tasks', () async {
      // Just test that close doesn't throw errors
      // Cleanup tasks start automatically in constructor
      await blobinator.close();
    });

    test('should handle version conflicts across stores', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];
      final wrongVersion = [1, 2, 3, 4, 5, 6, 7, 8];

      await blobinator.updateBlob(key, bytes1);
      final result = await blobinator.updateBlob(
        key,
        bytes2,
        version: wrongVersion,
      );

      expect(result, isFalse);
      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes1)));
    });
  });

  group('HybridBlobinator Configuration', () {
    test('should accept custom configuration with base blob config', () async {
      final config = HybridBlobinatorConfig(
        keyMaxLength: 1024,
        valueMaxLength: 2048,
        migrationAge: Duration(minutes: 10),
        cleanupInterval: Duration(minutes: 2),
      );

      final customBlobinator = HybridBlobinator(config: config);

      // Test that custom config doesn't throw errors
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      await customBlobinator.updateBlob(key, bytes);
      final blob = await customBlobinator.getBlob(key);
      expect(blob, isNotNull);

      await customBlobinator.close();
    });

    test('should enforce key length limits from config', () async {
      final config = HybridBlobinatorConfig(keyMaxLength: 5);

      final customBlobinator = HybridBlobinator(config: config);

      // Key longer than 5 bytes should fail
      final largeKey = [1, 2, 3, 4, 5, 6]; // 6 bytes
      final bytes = [4, 5, 6];

      expect(
        () => customBlobinator.updateBlob(largeKey, bytes),
        throwsA(isA<ArgumentError>()),
      );

      await customBlobinator.close();
    });
  });
}
