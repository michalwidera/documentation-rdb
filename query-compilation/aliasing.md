# Aliasing

When we join two data streams with the sum operator, a new data schema appears. We can refer to the successive values of this schema through the name of the data stream, indexed sequentially from the start of the schema.

We can, however, also use the names the stream was built from. A value can be pointed to both by the output stream's name, indexed from the start of the schema, and by the source stream's name, shifted relative to its join position.

The example uses the canonical declarations used throughout the chapter:

```rql
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
{{#include ../regen/out/alias.txt}}
```

`merged[0]` and `core0[0]` both end up as `PUSH_ID(merged[0])` — they are the same field. But `core1[0]` — the first field of `core1`'s schema — ends up as `PUSH_ID(merged[2])`, not `merged[0]`. The compiler translated the local index `core1[0]` into an absolute position in the combined schema: `core0` occupies positions 0 and 1, so `core1` starts at position 2.

## A reference outside the `FROM` clause

A source alias works only when the sum stands directly in the query's `FROM` clause. If the sum has been named by a separate query, the consumer's field list sees only that named stream:

```rql
SELECT * STREAM merged FROM core0 + core1
SELECT merged[0], core1[0] STREAM result FROM merged
```

Compilation ends with the error:

```
Check result:Stream 'result' refers to 'core1', which is not in its FROM clause. A field list reads only the streams named in FROM: refer to the field by its position in the record of a stream in FROM, or move the reference to a query whose FROM names 'core1'.
```

`merged` is a user query with its own interval and buffer, so the compiler does not determine the position of its sources in the `result` record. The correct form addresses the field by its position in the `merged` record — `core1` starts there at position 2:

```rql
SELECT merged[0], merged[2] STREAM result FROM merged
```

The restriction does not apply to substrates created automatically for a compound `FROM` clause, e.g. `FROM (core0 + core1) > 1`: source aliases still work through them.

## Index out of range

The index in `stream[k]` must point to a slot the query actually reads. The compiler rejects an index outside that range instead of producing a plan that reads past the end of the input record. The bound depends on what the name refers to:

| Reference | Bound | Accepted example | Rejected example |
|---|---|---|---|
| a stream in the `FROM` clause | the number of slots that stream contributes to `FROM` | `core1[1]` with `FROM core0 + core1` | `core1[2]` |
| a stream behind a window or a reducer | the number of slots after the operator, not the stream width | `core0[2]` with `FROM core0@(1,3)` | `core0[3]`; `acc[1]` with `FROM SUMC(acc)` |
| the query's own name in the `SELECT` list | the width of the `FROM` input record | `merged[3]` in `STREAM merged FROM core0 + core1` | `merged[4]` |
| the stream's own name in a `RULE` condition | the width of the stream's output record | `merged[3]` with `SELECT * STREAM merged` | `merged[4]` |

Windows and reducers change the slot count: `core0@(1,3)` contributes three slots although `core0` has two fields, and `SUMC(acc)` contributes one. The same count drives the expansion of `core0[_]`, so a hand-written index and the `_` form share one range.

Example messages:

```
Check result:Stream 'merged': stream 'core1' has 2 element(s) in its FROM clause, so 'core1[2]' is out of range
Check result:Stream 'merged': the FROM record of 'merged' has 4 element(s), so 'merged[4]' is out of range
Check result:Stream 'merged': rule 'alarm' reads the record of 'merged', which has 4 element(s), so 'merged[4]' is out of range
```

An index folded from `$` in a stream generator goes through the same check and produces the same message as a hand-written index.

## Aliasing after sum and interleave

The source aliases described above apply to the stream sum operator `+`. Sum concatenates schemas, so it preserves the position and identity of every component: `core0[0]` and `core1[0]` point to different locations in the output record.

The interleave operator `#` behaves differently. Its two arguments must have schemas of equal cardinality, and the result has one shared schema. In each slot the interleave selects a record from one component, so position `k` of the left and right arguments becomes the same position `k` of the result. After `A#B`, the name `A` or `B` can no longer identify the source of the current record.

Comparing compilation for the `core0` and `core1` declarations above shows the difference without executing the query:

| `FROM` expression | References in the `SELECT` list | Compilation result |
|---|---|---|
| `core0 + core1` | `core0[0]`, `core1[0]` | `PUSH_ID(merged[0])`, `PUSH_ID(merged[2])` — the schemas are concatenated, so the components remain distinguishable |
| `core0 # core1` | `core0[0]`, `core1[0]` | compilation error — both arguments share position `0` of the single output schema |

The second row corresponds to this query:

```rql
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

```rql
SELECT result[0], result[1] STREAM result FROM A#B
SELECT result2.* STREAM result2 FROM A#B
```

An unqualified `*` also denotes the complete output schema and remains legal. If a later computation needs `[_]`, name the interleave first and then use its result:

```rql
SELECT * STREAM interleaved FROM A#B
SELECT interleaved[_] * 2 STREAM scaled FROM interleaved
```

When a particular component is needed again, recover it with the de-interleave operator `&` or `%` instead of using a source name through a `#` node.

> **_NOTE:_** Aliasing after `+` is covered by the `Pattern7` integration test, and rejection of a reference outside `FROM` by the `field_ref_outside_from` test. Rejection of named `#` components and positive controls for the result name are covered by `ut_compiler` unit tests.
