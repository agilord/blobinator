# Changelog

## 0.1.1

- `flush` operation to move all or a subset of in-memory blobs to disk.
- Consistency fix: `BlobStorage.getSize()` returns `null` instead of `-1` when blob doesn't exist. (**Breaking change.**)

## 0.1.0

- Inital release.
