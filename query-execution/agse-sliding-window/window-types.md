# Window Types

By choosing its two parameters, the `@(k, w)` operator lets you build every one of the classic window types used in stream processing. Below is a comparison of the patterns on one shared source stream.

## Source stream

The file `data.txt` - 12 consecutive integers:

```
$ seq 1 12 > data.txt
```

The source declaration - one record per second, one field:

```rql
DECLARE val INTEGER STREAM src, 1 TEXTFILE 'data.txt'
```

## Tumbling window - non-overlapping windows

Hop equal to window size: `k = w`. Successive emitted windows do not overlap. Their phase follows from stamping by the window end, so an initial input prefix may precede the first complete window.

```rql
SELECT * STREAM tumbling FROM src@(4,4)
```

Output interval: `1s × 4 / 1 = 4s`. The first two output records:

```
$ xqry --null -s tumbling
5 4 3 2
9 8 7 6
```

The first record has logical index 1 and spans source positions 1..4, which contain values 2..5. A positive width puts the newest value first. Sample 1 precedes the first complete window of this partition.

Use cases: aggregating samples over fixed time intervals (e.g. per-minute, per-hour).

## Sliding window - overlapping windows

Hop smaller than window size: `k < w`. Every input element appears in several successive windows.

```rql
SELECT * STREAM sliding FROM src@(1,4)
```

Output interval: `1s × 1 / 1 = 1s`. Output records:

```
$ xqry --null -s sliding
4 3 2 1
5 4 3 2
6 5 4 3
7 6 5 4
...
```

Use cases: moving averages, trend detection, FIR filters (as in the [signal filter implementation](../../usage-examples/signal-filter-implementation.md)).

## Sampling - windows with gaps

Hop larger than window size: `k > w`. Some input elements are skipped.

```rql
SELECT * STREAM sampled FROM src@(3,1)
```

Output interval: `1s × 3 / 1 = 3s`. Output records:

```
$ xqry --null -s sampled
1
4
7
10
```

Use cases: signal decimation, sample-rate reduction, diagnostics on every Nth measurement.

## Mirrored window - reversed field order

A negative `w` value reverses the order of fields in the output record, while keeping the same window size.

```rql
SELECT * STREAM mirrored FROM src@(2,-2)
```

Output interval: `1s × 2 / 1 = 2s`. Output records (fields in reversed order):

```
$ xqry --null -s mirrored
2 3
4 5
6 7
8 9
...
```

Compare this with `src@(2,2)`, which would give `3 2`, `5 4`, `7 6` - the newest value first. A negative width preserves arrival order but does not change the phase of the partition into pairs. Phase alignment when reversing serialization is described in the [serialization example](serialization-example.md).

## Summary of patterns

| Query          | Window type | Interval | Record size | Overlap |
| -------------- | ---------- | -------- | --------------- | ---------- |
| `src@(4,4)`    | tumbling   | 4 s      | 4 fields         | none       |
| `src@(1,4)`    | sliding    | 1 s      | 4 fields         | full       |
| `src@(2,4)`    | hop window | 2 s      | 4 fields         | partial    |
| `src@(3,1)`    | sampling   | 3 s      | 1 field          | none       |
| `src@(2,-2)`   | mirrored   | 2 s      | 2 fields         | none       |

## Query execution plan

All four variants can be run at once by placing them in a single `.rql` file:

```rql
DECLARE val INTEGER STREAM src, 1 TEXTFILE 'data.txt'

SELECT * STREAM tumbling FROM src@(4,4)
SELECT * STREAM sliding  FROM src@(1,4)
SELECT * STREAM sampled  FROM src@(3,1)
SELECT * STREAM mirrored FROM src@(2,-2)
```

```
$ xretractor -c windows.rql -f -p -d > out.dot && dot -Tsvg out.dot -o out.svg
```

The query plan shows four independent branches originating from a shared `src` node. Each branch implements a different window type with no dependencies between them.

> **_NOTE:_** The functionality described here is covered by the tests: `agse1`, `agse2`, `agse3`, `Pattern6`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).
