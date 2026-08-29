# Aggregate Operators and Expression Functions

## Window aggregates (MIN, MAX, AVG, SUMC)

Aggregate operators operate on a stream with multiple fields — typically the output stream of the `@(k,w)` operator (a data window). They reduce all fields of the record to a single value.

### Syntax

```
FROM AGGREGATOR(stream_expression)
```

where `AGGREGATOR` is one of:

| Keyword        | Behavior |
|-----------------|-----------|
| `min`  / `MIN`  | minimum of all fields in the record |
| `max`  / `MAX`  | maximum of all fields in the record |
| `avg`  / `AVG`  | arithmetic mean of the record's fields |
| `sumc` / `SUMC` | sum of all fields in the record |

Keywords are accepted in both lowercase and uppercase. They are reserved, so a stream cannot be named `min`, `MAX`, `avg`, or `SUMC`.

The argument may be a complete stream expression rather than just one stream name. A window and its reduction can therefore be written without an auxiliary query:

```rql
SELECT * STREAM total FROM SUMC(src@(1,5))
```

The postfix forms `stream.min`, `.max`, `.avg`, and `.sumc` remain backward compatible but are deprecated. The parser emits a warning and recommends the function form. The existing `src@(1,5).sumc` syntax is valid, but new queries should use `SUMC(src@(1,5))`.

### Output interval

Aggregates do not change the stream's rate — the output interval is the same as the source's:

\\[\Delta_{result} = \Delta_{stream}\\]

### Example: moving average

```
DECLARE val INTEGER STREAM src, 1 FILE 'data.txt'

-- average of a 5-element window shifted by 1
SELECT * STREAM ma5 FROM AVG(src@(1,5))
```

The `ma5` stream contains, at every moment, the average of the five most recent `src` samples.

### Example: signal filter (sumc)

An excerpt from the signal-filter implementation example:

```
SELECT signalRow[_] * filter[_] STREAM accRow FROM signalRow+filter
SELECT accRow[0] STREAM output FROM SUMC(accRow)
```

`SUMC(accRow)` sums all fields of the `accRow` record (products of signal samples and filter coefficients), producing the output of an FIR filter.

### Example: MIN and MAX

```
DECLARE v INTEGER STREAM src, 0.1 FILE '/dev/urandom'
SELECT * STREAM min10 FROM MIN(src@(1,10))
SELECT * STREAM max10 FROM MAX(src@(1,10))
```

> **_NOTE:_** The functionality described here is covered by the tests: `simple_max`, `Pattern4`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).

---

## The to_string function

The `to_string` function converts a numeric expression to a text string of a given width. The result goes into a field of type STRING in the output stream.

### Syntax

```
to_string(expression : width)
to_string(expression)
```

The `width` parameter (a natural number after the colon `:`) specifies the output field's width in bytes. Omitting the parameter gives a default width of 32 bytes.

> **ℹ️ Info**
>
> The argument separator is a colon `:`, not a comma `,`. A comma is the SELECT list separator — using a comma in `to_string(x, n)` will cause a parse error.


### Example

```
DECLARE v INTEGER STREAM src, 1 FILE 'data.txt'

SELECT to_string(src[0]:10) STREAM labels FROM src
```

The `labels` stream contains the values of `src` formatted as text in a 10-byte field.

### Concatenation with a literal

The resulting string can be joined with a string literal using the `+` operator:

```
SELECT to_string(src[0]:8) + '_ok' STREAM tagged FROM src
```

Output field size: 8 (from `to_string`) + 3 (literal `_ok`) = 11 bytes.

### Use cases

`to_string` is useful when exporting to systems that accept text data (Graphite, InfluxDB via `xqry`), or when creating event labels combined with `DO DUMP` output.

> **_NOTE:_** The functionality described here is covered by the tests: `issue121_isnull`, `issue128_numeric_to_string`, `issue128_string_to_numeric`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).
