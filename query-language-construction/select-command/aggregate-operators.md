# Aggregate Operators

## Two aggregation axes (MIN, MAX, AVG, SUMC)

The same four keywords describe two different constructs. In `FROM`, a reducer folds the
fields of one current record. In the `SELECT` list, a record-history aggregate folds one
expression value evaluated for each consecutive historical record. The location therefore
determines whether reduction runs horizontally across fields or vertically across time.

## Current-record reducers in FROM

Stream reducers operate on a stream with multiple fields — typically the output of the
`@(k,w)` operator or a record that contains a numeric array. They reduce all flat slots of
one record to one value.

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

### Array fields and NULL values

A numeric declaration `T[N]` is one descriptor entry but occupies `N` flat record slots.
The reducer visits every one of them. This query therefore finds the minimum across all 24
cells in the current record, not just `cells[0]`:

```rql
DECLARE cells INTEGER[24] STREAM battery, 1 FILE 'cells.txt'
SELECT * STREAM cell_min FROM MIN(battery)
```

Derived stream schemas expand numeric arrays to scalar fields while preserving slot order
and byte layout. `STRING[N]`, by contrast, is one N-byte text field rather than an array of
N numbers.

NULL values are skipped. If every slot in the record is NULL, the reduction result is NULL,
not zero.

### Output interval

Aggregates do not change the stream's rate — the output interval is the same as the source's:

\\[\Delta_{result} = \Delta_{stream}\\]

### Result type

The result type depends on the input value type:

| Input type | Result type of `MIN`/`MAX`/`AVG`/`SUMC` |
| ---------- | --------------------------------------- |
| `BYTE`, `INTEGER`, `UINT`, `RATIONAL` | `RATIONAL` |
| `FLOAT` | `FLOAT` |
| `DOUBLE` | `DOUBLE` |

Integer and rational inputs are reduced as rational numbers, so `AVG` does not lose the
remainder. This also applies to `MIN` and `MAX`: the minimum of three sevens has type
`RATIONAL` and value `7/1`, not type `INTEGER`. `FLOAT` and `DOUBLE` preserve their types;
an artifact with such an input does not turn into a `RATIONAL` field.

A consumer of a `RATIONAL` field must know its numerator-denominator layout
(→ [The RATIONAL field layout](../../data-processing-system-architecture/data-storage-format/files.md#the-rational-field-layout))
or explicitly pass the result through `to_string`, `to_double`, or `to_integer`.

### Example: mean of an AGSE-window record

```
DECLARE val INTEGER STREAM src, 1 FILE 'data.txt'

-- AGSE builds a five-sample record; AVG reduces its five fields
SELECT * STREAM ma5 FROM AVG(src@(1,5))
```

The `ma5` stream contains, at every moment, the average of five consecutive `src` samples.
This is an AGSE operator composed with a record reducer, not the `SELECT`-list aggregate
described below.

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

> **_NOTE:_** Current-record reducers are covered by `simple_max`, `wide_from_names`,
> `agse_array`, and `array_derived`, described in the appendix
> [Integration Tests](../../appendices/integration-tests.md).

---

## Record-history aggregates in SELECT

### Syntax

```rql
SELECT expression_with_AGGREGATOR(record_value : width) \
STREAM result FROM source
```

`AGGREGATOR(record_value : width)` itself is an operand in an ordinary field expression.
It may be combined with literals, other fields, arithmetic operators, and scalar functions:

```rql
SELECT 2*MIN(a : 5)+1, null2zero(AVG(a+b : 5))-10 \
STREAM transformed FROM src
```

Only nesting a history aggregate inside another history aggregate is forbidden. `width` is
a positive number of records. For an output record with logical index `n`, the aggregate
evaluates `record_value` separately on source records `n-(width-1)` through `n`, then reduces
exactly those values. The window is end-stamped and advances by one record. The output
interval stays equal to the source interval, logical origin advances by `width-1`, and the
startup tail is inherited from the source.

```rql
DECLARE a INTEGER, b INTEGER STREAM src, 1 FILE 'data.txt'

SELECT MIN(a : 5), MAX(a : 5), AVG(a+b : 5), SUMC(a : 5) \
STREAM stats FROM src
```

Several aggregates over the same expression, source, and width share one history scan.
NULL values are skipped; a window with no present value yields NULL. The result follows the
same type-promotion table as a current-record reducer, and that type is preserved through
pure copies, shifts, and other schema-copying operators.

### Argument restrictions

The argument must be a numeric expression that reads at least one field of one stored
source. A query containing a record-history aggregate must have one plain stream reference
in `FROM`. The compiler rejects:

- a non-positive width;
- a text expression or a constant that reads no field;
- an expression that mixes histories from several streams;
- a nested history aggregate or an aggregate in a `RULE` condition;
- a compound `FROM` clause such as `FROM src - 2`;
- a bare numeric-array name.

For `DECLARE a INTEGER[3]`, select one channel, for example `MIN(a[0] : 5)`.
`MIN(a : 5)` does not mean all array elements from every record and is rejected. Reduce all
elements of one record separately with `FROM MIN(stream)`.

### Hopping windows

A `SELECT` aggregate has no step argument. Build a hopping window by decimating the
completed window stream with `-` in a second node:

```rql
SELECT MIN(a : 5) STREAM sliding FROM src
SELECT * STREAM hopping FROM sliding - 2
```

The argument of `-` is the target output interval. For hop H over a source interval
\(\Delta\), pass \(H\Delta\). Splitting the construction preserves five consecutive
records in every window and only then selects every H-th result. Direct
`SELECT MIN(a : 5) ... FROM src - 2` is not shorthand for this construction and does not
compile.

> **_NOTE:_** Syntax, types, boundaries, shared computations, expressions, NULL values,
> and restrictions are covered by `window_aggregate` and by the `ut_compiler` and
> `ut_expeval` unit tests.

---

## Further computation on an aggregate result

Scalar functions belong to field-expression syntax, not to either kind of window. The full
list, name and arity rules, and type semantics are documented in
[Field Expressions and Scalar Functions](field-expressions-and-scalar-functions.md). Only
conversions particularly relevant when consuming an aggregate result remain below.

`isnull(x)` returns 1 for NULL and 0 for a present value. `null2zero(x)` maps NULL to integer
zero but passes a present value without changing its type. It is a lossy conversion, not a
way to export missingness. Division by zero yields NULL for every numeric type and does not
stop later stream processing.

## Conversion example: to_string

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

## Conversion example: to_integer

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
