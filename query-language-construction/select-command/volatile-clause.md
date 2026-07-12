# VOLATILE Clause

The `VOLATILE` clause in the `SELECT` command creates a stream that holds only a single record in memory. On disk, only the `.desc` descriptor file describing the data schema appears — the data itself is never written.

## Behavior

```
SELECT expression STREAM name FROM source VOLATILE
```

Internally, the compiler sets the storage type to `MEMORY` with a capacity of `1`:

```cpp
if (ctx->VOLATILE()) {
    qry.policy = std::make_pair("MEMORY", 1);
}
```

This means that:

* the in-memory buffer always holds only the single, most recent record,
* data never reaches disk,
* the `.desc` descriptor is still created — other processes can learn the stream's schema.

## Difference from `STORAGE MEMORY`

| Property              | `VOLATILE`      | `STORAGE MEMORY`         |
| ---------------------- | ---------------- | ------------------------- |
| Buffer capacity         | always 1 record  | depends on `RETENTION`    |
| `RETENTION` clause      | ignored          | applied                   |
| Descriptor on disk      | yes              | yes                        |
| Data on disk            | no               | no                         |

`VOLATILE` is useful when the query result is being pulled by `xqry` on an ongoing basis and history is not needed — e.g. the current value of a sensor exposed by the operating system.

## Example

```
DECLARE a INTEGER STREAM sensor, 0.1 FILE '/dev/sensor0'

SELECT sensor[0] * 100 STREAM scaled VOLATILE
```

The `scaled` stream contains, at every moment, a single, current value. The `xqry` process can read it via shared memory.
