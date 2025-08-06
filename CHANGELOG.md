# Changelog

## 0.2.0

- New `flush` parameter semantics: specifies the suggested time to flush to disk (but not after the global `mem-ttl` is applied).

## 0.1.2

- `flush` parameter on updating a blob will immediately write it to disk.
- Expanded character set for blob ids.

## 0.1.1

- `flush` operation to move all or a subset of in-memory blobs to disk.
- Implemented a `blobId` cache to reduce disk access.
- Consistency fix: `BlobStorage.getSize()` returns `null` instead of `-1` when blob doesn't exist. (**Breaking change.**)

## 0.1.0

- Inital release.
