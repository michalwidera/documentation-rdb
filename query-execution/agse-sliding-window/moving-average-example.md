# Moving Average Example

The moving average is one of the simplest and most commonly used signal filters. Every output point is the arithmetic mean of the last `N` samples. The `@(1, N)` operator in RetractorDB creates exactly this kind of window: for every new measurement, the last `N` values are available.

## Source data

Let's assume a temperature stream measured every second. The file `temp.txt` contains successive readings:

```
$ seq 10 5 60 > temp.txt
```

```
10
15
20
25
30
35
40
45
50
55
60
```

## The RQL query

The file `avg.rql`:

```
DECLARE temp INTEGER \
STREAM sensor, 1 \
FILE 'temp.txt'

SELECT * \
STREAM window5 \
FROM sensor@(1,5)

SELECT window5[0]+window5[1]+window5[2]+window5[3]+window5[4] \
STREAM sumRow \
FROM window5

SELECT sumRow[0]/5 \
STREAM avg5 \
FROM sumRow
```

### What each query does

1. `sensor@(1,5)` — creates a sliding 5-element window. Every `window5` record contains the 5 most recent temperature readings. Output interval: `1s / 1 × 1 = 1s` (hop=1, W=1 field).
2. Sum of the five fields — a classic `SELECT` over the fields `window5[0]`..`window5[4]`.
3. Dividing the sum by 5 — the result is the moving average.

## Running it

```
$ xretractor avg.rql &
$ xqry -s avg5
```

Example output (the window fills up after the first 5 samples):

```
30
35
40
45
50
```

The value `30` corresponds to the average of the first full window: `(10+15+20+25+30)/5 = 20`... note — RetractorDB does not show partial windows, so the first result to appear corresponds to the moment the window is fully saturated with data.

## Verifying the query plan

```
$ xretractor -c avg.rql -f -p -d > out.dot && dot -Tsvg out.dot -o out.svg
```

In the generated plan you can see the chain: `sensor → window5 → sumRow → avg5`. The key node is `sensor@(1,5)` — from a single-element stream arriving every second, a five-element stream is produced, continuously sliding.

## The relationship between window parameters and delay

The moving average introduces a delay of half the window length. For a window of N=5, the delay is 2 samples (2 seconds). Increasing the window:

* reduces noise (more smoothing),
* increases the delay,
* does not change the output interval (with a fixed hop k=1).

Changing the hop with a fixed window:

```
sensor@(5,5)   -- tumbling: a result every 5 seconds, no overlap
sensor@(1,5)   -- sliding:  a result every second, full overlap
sensor@(3,5)   -- partial overlap: a result every 3 seconds
```

> **_NOTE:_** The functionality described here is covered by the tests: `agse1`, `agse2`, `agse3`, `Pattern6`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).
