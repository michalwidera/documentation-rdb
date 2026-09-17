# VOLATILE Clause

The `VOLATILE` clause in the `SELECT` command creates a stream stored in memory. On disk, only the `.desc` descriptor file describing the data schema appears — the data itself is never written.

## Default volatility and the PERSISTENT exception

`DEFAULT VOLATILE` selects in-memory storage for `SELECT` results without an
explicit policy and for compiler-generated substrates. It replaces repeated
`VOLATILE` clauses and the `SUBSTRAT 'memory'` directive:

```rql
DEFAULT VOLATILE
DECLARE a INTEGER STREAM sensor, 0.1 FILE '/dev/sensor0'
SELECT sensor[0]*100 STREAM scaled  FROM sensor
SELECT scaled[0]     STREAM history FROM scaled PERSISTENT
```

`scaled` stays in memory, while `history` writes data to disk using the usual
`FILE`, `RETENTION`, and `STORAGE` settings. `PERSISTENT` affects only that
`SELECT` result; its substrates still inherit the default volatility.

The directive may appear once, before the first `DECLARE`, `SELECT`, or `RULE`.
It does not change `DECLARE` sources. Programs without it retain their existing
settings. `VOLATILE` and `PERSISTENT` are mutually exclusive clauses.

An explicit `STORAGE profile` on a `SELECT` overrides the default; for example,
`STORAGE DEFAULT` selects ordinary file storage. Explicit `VOLATILE` retains its
precedence over `STORAGE`. Combining `PERSISTENT STORAGE MEMORY` is an error.
Explicit `SUBSTRAT 'profile'` selects substrate storage regardless of the order
of the two directives in the header. `FILE` or `RETENTION` alone does not disable
default volatility: add `PERSISTENT` to store history.

## Behavior

```rql
SELECT expression STREAM name FROM source VOLATILE
```

The parser initially sets the storage type to `MEMORY` with a capacity of `1`:

```cpp
if (ctx->VOLATILE()) {
    qry.policy = std::make_pair("MEMORY", 1);
}
```

The compiler then determines the capacity required by the plan. If another stream reads the
history of a `VOLATILE` result, the buffer may hold more than one record. This means that:

* the in-memory buffer holds at least the most recent record and any history its consumers need,
* data never reaches disk,
* the `.desc` descriptor is still created — other processes can learn the stream's schema.

## Difference from `STORAGE MEMORY`

| Property           | `VOLATILE`                                      | `STORAGE MEMORY`                         |
| ------------------ | ----------------------------------------------- | ---------------------------------------- |
| Buffer capacity    | initially 1 record; may grow to meet plan needs | depends on `RETENTION` and plan needs    |
| `RETENTION` clause | ignored                                         | applied                                  |
| Descriptor on disk | yes                                             | yes                                      |
| Data on disk       | no                                              | no                                       |

`VOLATILE` is useful when the query result is being pulled by `xqry` on an ongoing basis and history is not needed — e.g. the current value of a sensor exposed by the operating system.

## Example

```rql
DECLARE a INTEGER STREAM sensor, 0.1 FILE '/dev/sensor0'

SELECT sensor[0] * 100 STREAM scaled FROM sensor VOLATILE
```

The `scaled` stream contains, at every moment, a single, current value. The `xqry` process can read it via shared memory.
