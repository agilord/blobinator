import 'dart:async';
import 'storage.dart';

class EvictionScheduler {
  final BlobStorage storage;
  Timer? _memoryTimer;
  Timer? _diskTimer;

  EvictionScheduler(this.storage);

  void start() {
    _memoryTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _runMemoryEviction(),
    );

    _diskTimer = Timer.periodic(
      const Duration(hours: 8),
      (_) => _runDiskEviction(),
    );

    _runMemoryEviction();
    _runDiskEviction();
  }

  void stop() {
    _memoryTimer?.cancel();
    _diskTimer?.cancel();
  }

  Future<void> _runMemoryEviction() async {
    try {
      await storage.checkMemoryTtl();
    } catch (e) {
      print('Error during memory eviction: $e');
    }
  }

  Future<void> _runDiskEviction() async {
    try {
      await storage.checkDiskLimits();
    } catch (e) {
      print('Error during disk eviction: $e');
    }
  }
}
