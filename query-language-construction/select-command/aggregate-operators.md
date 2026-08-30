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

### Result type

All four reducers produce a field of type `RATIONAL`, regardless of the type of the input
fields. This holds for `MIN` and `MAX`, which return a value already present in the record,
and also when the result happens to be a whole number — the mean of three sevens is a
`RATIONAL` field holding `7/1`, not an `INTEGER` field.

The choice of type is not cosmetic: the reduction is computed over rational numbers, so `AVG`
does not lose the remainder and the result stays exact. The price is that an artifact holding
an aggregate requires the reader to know the numerator-denominator layout
(→ [The RATIONAL field layout](../../data-processing-system-architecture/data-storage-format/files.md#the-rational-field-layout))
or to pass the value through `to_string`, `to_double` or `to_integer`.

### Example: moving average

```
DECLARE val INTEGER STREAM src, 1 FILE 'data.txt'

-- average of a 5-element window shifted by 1
SELECT * STREAM ma5 FROM AVG(src@(1,5))
```

The `ma5` stream contains, at every moment, the average of the five most recent `src` samples.

### Example: signal filter (sumc)

An excerpt from the signal-filter implementation example:

```rql
SELECT source[_] * filter[_] STREAM accRow FROM source@(1,25)+filter
SELECT accRow[0] STREAM output FROM SUMC(accRow)
```

The window appears directly in `FROM`, so it does not require a separate query. `source[_]` expands according to the 25 slots contributed to the input record by `source@(1,25)`. `SUMC(accRow)` sums all fields of the `accRow` record — the products of signal samples and filter coefficients — producing the output of an FIR filter.

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

---

## The to_integer function

The `to_integer` function converts a numeric expression into a field of type `INTEGER`. It is
the primary way of reading an artifact that holds an aggregate: it turns a `RATIONAL` field
into a whole number the reader can consume without knowing the numerator-denominator layout.

### Syntax

```
to_integer(expression)
```

### Rounding

> **⚠️ Warning**
>
> `to_integer` **truncates toward zero**; it does not floor. For negative values the result
> differs from the floor by one.

The rule is the same for a rational and for a floating-point argument — in both cases the
fractional part is dropped and the sign is kept:

| Input value | `to_integer` | floor (for comparison) |
| ----------- | ------------ | ---------------------- |
| `8/3`       | `2`          | `2`                    |
| `-8/3`      | `-2`         | `-3`                   |
| `-4/3`      | `-1`         | `-2`                   |
| `-2.6666…`  | `-2`         | `-3`                   |

A `NULL` passes through unchanged — `to_integer(NULL)` yields `NULL`, not zero.

### A pitfall when porting to Python

Python's `//` operator **floors**, so a naive transcription of the query diverges from the
engine on every negative value:

```python
>>> -8 // 3        # Python: floor
-3
>>> int(-8 / 3)    # what to_integer does
-2
```

A model reproducing the engine's behavior has to compute the truncated mean explicitly:

```python
def truncated_mean(values):
    """Truncate toward zero, matching the cast applied to the rational window mean."""
    total = sum(values)
    quotient = abs(total) // len(values)
    return quotient if total >= 0 else -quotient
```

The same problem arises in any language whose integer division floors.

### Use cases

`to_integer` fits wherever the consumer of the artifact expects a whole number and the
fractional part is not needed. Where the value must stay exact, the right choice is
`to_string`, which writes the fraction as the text `numerator/denominator`, or reading the
pair directly
(→ [The RATIONAL field layout](../../data-processing-system-architecture/data-storage-format/files.md#the-rational-field-layout)).

> **_NOTE:_** The functionality described here is covered by the test `issue128_string_to_numeric`, described in the appendix [Integration Tests](../../appendices/integration-tests.md), and by the unit tests `ut_payload` and `ut_convertTypes`, which pin the `RATIONAL` field layout and the rounding rule.
