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

`merged[0]` and `core0[0]` both end up as `PUSH_ID(merged[0])` — they are the same field. But `core1[0]` — the first field of `core1`'s schema — ends up as `PUSH_ID(merged[2])`, not `merged[0]`. The compiler translated the local index `core1[0]` into an absolute position in the combined schema: `core0` occupies positions 0 and 1, so `core1` starts at position 2.

## Aliasing after sum and interleave

The source aliases described above apply to the stream sum operator `+`. Sum concatenates schemas, so it preserves the position and identity of every component: `core0[0]` and `core1[0]` point to different locations in the output record.

The interleave operator `#` behaves differently. Its two arguments must have schemas of equal cardinality, and the result has one shared schema. In each slot the interleave selects a record from one component, so position `k` of the left and right arguments becomes the same position `k` of the result. After `A#B`, the name `A` or `B` can no longer identify the source of the current record.

Comparing compilation for the `core0` and `core1` declarations above shows the difference without executing the query:

| `FROM` expression | References in the `SELECT` list | Compilation result |
|---|---|---|
| `core0 + core1` | `core0[0]`, `core1[0]` | `PUSH_ID(merged[0])`, `PUSH_ID(merged[2])` — the schemas are concatenated, so the components remain distinguishable |
| `core0 # core1` | `core0[0]`, `core1[0]` | compilation error — both arguments share position `0` of the single output schema |

The second row corresponds to this query:

```
SELECT core0[0], core1[0] STREAM interleaved FROM core0#core1
```

The compiler stops with a message that `core0` is an interleave component and that this reference cannot be distinguished from a reference to the other component. It does not create a plan that silently maps both fields to `interleaved[0]`.

The compiler therefore rejects user-written named references that try to reach an interleave component through `#`. The restriction covers every form:

- numeric index: `A[0]`;
- field name: `A.field`, and a bare field name resolved to `A`;
- index wildcard: `A[_]`;
- qualified full scan: `A.*`;
- the same references in a `RULE` condition and through substrates generated for a compound `FROM` clause.

The correct form refers to the only schema that exists after the interleave:

```
SELECT result[0], result[1] STREAM result FROM A#B
SELECT result2.* STREAM result2 FROM A#B
```

An unqualified `*` also denotes the complete output schema and remains legal. If a later computation needs `[_]`, name the interleave first and then use its result:

```
SELECT * STREAM interleaved FROM A#B
SELECT interleaved[_] * 2 STREAM scaled FROM interleaved
```

When a particular component is needed again, recover it with the de-interleave operator `&` or `%` instead of using a source name through a `#` node.

> **_NOTE:_** Aliasing after `+` is covered by the `Pattern7` integration test. Rejection of named `#` components and positive controls for the result name are covered by `ut_compiler` unit tests.
