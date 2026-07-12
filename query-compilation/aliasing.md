# Aliasing

When we join two data streams with the sum operator, a new data schema appears. We can refer to the successive values of this schema through the name of the data stream, indexed sequentially from the start of the schema.

We can, however, also use the names the stream was built from. A value can be pointed to both by the output stream's name, indexed from the start of the schema, and by the source stream's name, shifted relative to its join position.

The example uses the canonical declarations used throughout the chapter:

```
DECLARE a BYTE, b INTEGER \
STREAM core0, 0.1 \
FILE 'sensor_a.txt'

DECLARE c INTEGER, d FLOAT \
STREAM core1, 0.2 \
FILE 'sensor_b.txt'

SELECT merged[0], merged[2], core0[0], core1[0] \
STREAM merged \
FROM core0 + core1
```

After compilation we get:

```
$ xretractor -c query.rql
merged(1/10)
        :- PUSH_STREAM(core0)
        :- PUSH_STREAM(core1)
        :- STREAM_ADD
        merged_0: BYTE
                PUSH_ID(merged[0])
        merged_1: INTEGER
                PUSH_ID(merged[2])
        merged_2: BYTE
                PUSH_ID(merged[0])
        merged_3: INTEGER
                PUSH_ID(merged[2])
core0(1/10)     sensor_a.txt
        a: BYTE
        b: INTEGER
core1(1/5)      sensor_b.txt
        c: INTEGER
        d: FLOAT
```

`merged[0]` and `core0[0]` both end up as `PUSH_ID(merged[0])` — they are the same field. But `core1[0]` — the first field of `core1`'s schema — ends up as `PUSH_ID(merged[2])`, not `merged[0]`. The compiler translated the local index `core1[0]` into an absolute position in the combined schema: `core0` occupies positions 0 and 1, so `core1` starts at position 2. What if we replace the `+` operator with `#`? I encourage you to experiment.

> **_NOTE:_** The functionality described here is covered by the test: `Pattern7`, described in the appendix [Integration Tests](../appendices/integration-tests.md).
