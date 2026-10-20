# AGSE Sliding Data Window

A sliding data window is a concept widely used in systems that process streams or time series. The idea is to group data into time windows, giving the user the ability to process it in frozen snapshots.

RetractorDB supports this data-processing model through the **AgSe** operator (Aggregation and Serialization). This operator is two-argument and operates on a stream. Denoted with the `@` symbol, it has the form:

```
stream@(k, w)
```

where:

* **k** - the window's hop (a positive natural number): by how many elements of the flattened stream the window shifts on every step,
* **w** - the window size (a non-zero integer): how many elements a single output record contains.

Flattening includes every element of a numeric array. A record containing `INTEGER[3]` contributes three elements, while `STRING[N]` contributes one text element. A hop counted in records equals a hop counted in elements only for a single-element source.

A positive `w` follows RetractorDB's historical convention: the newest window field comes first. A negative value means **mirrored aggregation** - it reverses that order, placing fields in arrival order.

## How the output stream's interval changes

If the source stream has `W` flattened elements per record and interval `Δ`, the output stream of the `@(k, w)` operator has:

* `|w|` fields per output record,
* an output interval `Δ_out = (Δ / W) × k`.

| Parameters          | Effect                                                          |
| ------------------- | -------------------------------------------------------------- |
| `k = \|w\|`        | a tumbling window - successive windows do not overlap            |
| `k < \|w\|`        | a sliding window - successive windows overlap                     |
| `k > \|w\|`        | sampling with gaps - some data is skipped                          |
| `k = 1, \|w\| = 1` | serialization - a multi-field record is split into single-element ones |
| `w < 0`            | mirrored aggregation - arrival order, oldest field first |

## Typical usage patterns

```rql
# serialization: 2 fields → 1 field (interval ÷ 2)
SELECT * STREAM s1 FROM A@(1,1)

# tumbling window: 4 elements, no overlap
SELECT * STREAM s2 FROM A@(4,4)

# sliding window: a 5-element window shifted by 1
SELECT * STREAM s3 FROM A@(1,5)

# sampling: every fifth flattened element
SELECT * STREAM s4 FROM A@(5,1)

# deserialization: align pairs and restore arrival order
SELECT * STREAM s5 FROM (s1>1)@(2,-2)
```

## Visualizing the @ operator

Below is a schematic representation of how `source@(k, w)` behaves for a single-element stream:

```
Input data:       0  1  2  3  4  5  6  7  8  9  ...
                  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓

@(1, 3) - sliding window, hop=1, window=3:
  [2,1,0]  [3,2,1]  [4,3,2]  [5,4,3]  ...

@(3, 3) - tumbling window, hop=3, window=3:
  [3,2,1]           [6,5,4]           ...

@(5, 1) - sampling every 5 elements:
  [0]               [5]               ...

@(2,-2) - mirrored, hop=2, window=2:
  [1,2]    [3,4]    [5,6]    [7,8]    ...
```

The window is stamped by the interval **end**: the record with logical index `n` spans positions `n·k−(|w|−1) … n·k`, so its newest field lies exactly at position `n·k`. The window's logical index therefore denotes the same instant as the source's logical index, and joining a window with its own source (a FIR pipeline) does not lead the signal. The illustration above shows the sequence of emitted windows; the first of them carries index `origin`, not zero.

With `k = |w|`, emitted windows do not overlap, but their partition need not start at the source's first element. For `@(3,3)`, the first complete record has index 1 and spans positions 1..3. Changing the sign of `w` reverses field order without changing the phase; pair alignment during deserialization is shown in the [serialization example](serialization-example.md).

AGSE emits only complete windows. Initial slots in which the window would reach before the start of the source **are not records and have no definition** - they form the `origin=` reported in the plan. Slots in which the window is defined but its newest field has not yet been produced form the `tail=`. A genuine `NULL` in source data remains an element of the complete window. The formal tail and history capacity bounds are given in [Tails, Logical Origins and Operator Observability](../../mathematical-foundations/operator-tails-and-observability.md).

## Examples

The subchapters below present concrete uses of the AgSe operator:

* **Serialization Example** - turning a multi-field record into a sequence of single-element records and back again through phase alignment and mirrored aggregation.
* **Moving Average Example** - a sliding window as the basis for a signal-averaging filter.
* **Window Types** - tumbling, sliding, and sampling on the same data stream.

The examples' `xqry --null` commands skip rows whose fields are all `NULL`, including IPC notifications before the first complete window. The filter also skips genuine results whose fields are all `NULL`; omit this option to observe them. The receive contract is described in [xqry options](../../appendices/command-line-options/xqry.md).

We'll start by considering the serialization process using the Aggregation and Serialization operator - AgSe.

> **_NOTE:_** The functionality described here is covered by the tests: `agse1`, `agse2`, `agse3`, `Pattern6`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).
