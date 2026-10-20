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

```rql
DECLARE temp INTEGER STREAM sensor, 1 TEXTFILE 'temp.txt'

SELECT * STREAM avg5 FROM AVG(sensor@(1,5))
```

### What the query does

1. `sensor@(1,5)` creates a sliding window of the five most recent temperature readings. Its output interval is `(1s / 1) × 1 = 1s`, because the source has one element per record.
2. `AVG(...)` reduces the five fields of each complete window to their mean. For `INTEGER` input, the result is `RATIONAL`, preserving the fractional part.

Manually adding `INTEGER` fields and dividing by integer `5` would truncate the result: for `[1,1,1,1,2]` it would give `1`, while `AVG` gives exactly `6/5`. `NULL` values are skipped; a window with no present values produces `NULL`. Another way to express this mean is the history aggregate `SELECT AVG(temp : 5) STREAM avg5 FROM sensor`, described in [Aggregate Operators](../../query-language-construction/select-command/aggregate-operators.md).

## Running it

```
$ xretractor avg.rql --xqrywait &
$ xqry --null -s avg5
```

Example output (the window fills up after the first 5 samples):

```
20/1
25/1
30/1
35/1
40/1
45/1
50/1
```

The first stored result is `(10+15+20+25+30)/5 = 20`, printed as the fraction `20/1`. An artifact record is produced only after obtaining a complete window. `--xqrywait` holds startup until the first client command, allowing the subscription to include the first result. `--null` skips the initial `NULL` rows delivered over IPC in the client's output; it also skips genuine results whose fields are all `NULL`.

## Verifying the query plan

```
$ xretractor -c avg.rql -f -p -d > out.dot && dot -Tsvg out.dot -o out.svg
```

The generated plan contains the `sensor` source, an AGSE window substrate and the reducer producing `avg5`. The window has five fields, while the mean has one `RATIONAL` field. The compiler extracts the substrate without requiring a separate name in the query.

## The relationship between window parameters and delay

With complete data, a moving average of length N has a group delay of `(N-1)/2` samples. For N=5, this is 2 samples (2 seconds). This filter property is distinct from waiting for the first complete window and from the plan's startup tail. Increasing the window:

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
