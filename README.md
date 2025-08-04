Dart package and standalone HTTP service for temporary binary blob storage.

## Why?

Blobinator provides a simple way to exchange temporary binary data between systems. It's designed for:
- **Temporary data exchange** - Binary blobs with random identifiers, no metadata required
- **Short-lived storage** - Data may be evicted or lost, applications must handle retries
- **Expendable content** - Data written to disk can be deleted automatically
- **Processing pipelines** - Intermediate data storage between processing steps

**⚠️ Do not use for permanent storage - data will be automatically evicted.**

## Features

### Two-Tier Storage
- **Memory tier**: Fast access for recent blobs
- **Disk tier**: Slower access for evicted blobs
- **Automatic promotion**: Memory → Disk when limits reached
- **Configurable limits**: Items, size, and TTL for each tier

### Configuration
- **Memory**: 1M items, 1 GiB, 3 days TTL (default)
- **Disk**: 100M items, 512 GiB, 90 days TTL (default)
- **Flexible units**: `1m` items, `2GiB` size, `6h` TTL
- **Optional disk storage**: Memory-only mode available

### HTTP API
- **`GET /blobs/{id}`** - Retrieve blob data
- **`PUT /blobs/{id}`** - Store blob data
- **`HEAD /blobs/{id}`** - Get metadata (size, last-modified)
- **`DELETE /blobs/{id}`** - Remove blob
- **`GET /status`** - Service statistics and metrics

### Blob IDs
- **Characters**: `[a-z0-9._-]` only
- **Length**: 4-512 characters
- **Client-generated**: No collision detection, use sufficiently random IDs

### Eviction Strategy
- **Memory limits**: Checked after every write
- **Memory TTL**: Checked hourly
- **Disk limits**: Checked every 8 hours  
- **Algorithm**: Oldest entries evicted first (by last-modified time)
- **Statistics**: 7-day eviction history (in-memory only)

## CLI use

Start the blobinator service:

```bash
# Basic usage (defaults: memory-only, port 8080)
dart run blobinator serve

# With disk storage
dart run blobinator serve --disk-storage-path ./blobs

# Custom configuration
dart run blobinator serve \
  --port 3000 \
  --mem-items 500k \
  --mem-size 2GiB \
  --mem-ttl 6h \
  --disk-items 50m \
  --disk-size 1TB \
  --disk-ttl 30d \
  --disk-storage-path ./data/blobs
```

**Unit formats:**
- **Items**: `k` (thousands), `m` (millions), `b` (billions)
- **Size**: `KiB/KB` (kilobytes), `MiB/MB` (megabytes), `GiB/GB` (gigabytes)
- **TTL**: `s` (seconds), `m` (minutes), `h` (hours), `d` (days)

## HTTP client use

```dart
import 'package:blobinator/blobinator.dart';

final client = BlobinatorClient('http://localhost:8080');

// Store and retrieve bytes
await client.putBytes('my-blob', [1, 2, 3, 4]);
final data = await client.getBytes('my-blob'); // Uint8List?

// Store and retrieve files (streaming)
await client.putFile('large-blob', './input.dat');
await client.getFile('large-blob', './output.dat'); // bool (success)

// Check existence and metadata
final exists = await client.exists('my-blob'); // bool
final size = await client.getSize('my-blob'); // int?
final lastMod = await client.getLastModified('my-blob'); // DateTime?

// Get detailed metadata
final metadata = await client.head('my-blob'); // BlobMetadata?

// Delete blobs
await client.delete('my-blob'); // bool (found and deleted)

// Service status
final status = await client.getStatus(); // ServiceStatus

// Clean up
client.close();
```
