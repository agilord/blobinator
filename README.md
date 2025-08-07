# Blobinator

**Tools and HTTP service for temporary binary blob storage.**

Blobinator is a Dart package that provides a key-value store for binary data with versioning, TTL (time-to-live), and HTTP API support. Perfect for temporary file storage, caching, and data exchange.

## Features

- **Multiple Storage Backends**: In-memory SQLite, file-based SQLite, and hybrid (memory + disk, experimental)
- **Versioning**: Optimistic concurrency control with automatic version generation
- **TTL Support**: Automatic expiration and cleanup of expired blobs
- **HTTP API**: RESTful endpoints for blob operations via built-in server
- **CLI Tools**: Command-line interface for both server and client operations
- **Performance**: Optimized SQLite configuration with WAL mode and maintenance tasks

## Quick Start

### As a Library
```dart
import 'package:blobinator/blobinator.dart';

// Create in-memory storage
final blobinator = await Blobinator.inMemory();

// Store binary data
final key = 'my-key'.codeUnits;
final data = 'Hello, World!'.codeUnits;
await blobinator.updateBlob(key, data, ttl: Duration(minutes: 30));

// Retrieve data
final blob = await blobinator.getBlob(key);
print(utf8.decode(blob!.bytes)); // Hello, World!

// Clean up
await blobinator.close();
```

### HTTP Server
```bash
# Start server with in-memory storage
dart run blobinator serve --port 8080

# Start with file-based storage
dart run blobinator serve --port 8080 --path /path/to/storage.db

# Start with hybrid storage (memory cache + disk persistence)
dart run blobinator serve --port 8080 --hybrid --path /path/to/storage.db
```

### CLI Client
```bash
# Store blob from file
dart run blobinator client --url http://localhost:8080 update --key mykey --input data.bin --ttl 1h

# Retrieve blob to stdout
dart run blobinator client --url http://localhost:8080 get --key mykey

# Get metadata
dart run blobinator client --url http://localhost:8080 get-metadata --key mykey

# Delete blob
dart run blobinator client --url http://localhost:8080 delete --key mykey

# Server status
dart run blobinator client --url http://localhost:8080 status
```

## Storage Backends

- **In-Memory**: Fast, volatile storage using SQLite's `:memory:` database
- **File-Based**: Persistent SQLite database stored on disk
- **Hybrid**: Combines fast in-memory access with automatic migration to disk for persistence

## HTTP API

- `GET /status` - Server statistics
- `HEAD /blobs/{key}` - Blob metadata
- `GET /blobs/{key}` - Retrieve blob
- `PUT /blobs/{key}` - Create/update blob
- `DELETE /blobs/{key}` - Delete blob

Supports UTF-8 and base64-encoded keys, version-based updates, and TTL parameters.

## Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  blobinator: ^0.1.2
```

Or install globally:
```bash
dart pub global activate blobinator
```

## Configuration

```dart
final config = BlobinatorConfig(
  keyMaxLength: 1024,        // Maximum key size
  valueMaxLength: 10 * 1024, // Maximum value size  
  defaultTtl: Duration(hours: 1), // Default expiration
);
```

## Example

See `example/example.dart` for a comprehensive demonstration of HTTP client usage including:
- Basic CRUD operations
- Version-based optimistic concurrency control
- TTL functionality
- Different key formats (UTF-8, binary, special cases)
- Error handling and edge cases

```bash
dart run example/example.dart
```

For more details, see the API documentation and examples in the repository.