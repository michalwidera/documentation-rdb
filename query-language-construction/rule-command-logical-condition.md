# Logical Condition in RULE

The `WHEN` clause of the `RULE` command takes a logical expression, which is evaluated on every new record of the specified stream. If the expression evaluates to true, the process defined in the `DO` clause is triggered.

## Comparison operators

| Operator | Meaning              |
| -------- | -------------------- |
| `=`      | equal                |
| `!=`     | not equal            |
| `>`      | greater than         |
| `<`      | less than            |
| `>=`     | greater than or equal |
| `<=`     | less than or equal    |

## Logical connectives

| Operator | Meaning |
| -------- | ------- |
| `AND`    | conjunction — both conditions must be satisfied |
| `OR`     | disjunction — one condition is enough            |
| `NOT`    | negation — the condition must not be satisfied   |

## Expression structure

A condition is built from the fields of the stream schema specified in the `ON` clause. Fields are identified the same way as in `SELECT` — by the stream name with an index:

```
WHEN stream[index] operator value
```

Compound conditions are joined with connectives:

```
WHEN stream[0] > 10 AND stream[1] != 0
WHEN stream[0] = 5 OR stream[0] = 7
WHEN NOT stream[0] < 0
```

## Examples

```
RULE high_alarm \
ON measurements \
WHEN measurements[0] > 100 OR measurements[0] < -100 \
DO DUMP -10 TO 10 RETENTION 50

RULE signaling \
ON status \
WHEN status[0] = 1 AND status[1] != 0 \
DO SYSTEM 'systemctl restart sensor-reader'

RULE one_time \
ON data \
WHEN NOT data[0] = 0 \
DO DUMP -5 TO 0
```

## Field access

The condition refers to the fields of the stream specified in `ON`. The field index corresponds to its position in that stream's schema — the same as in the `SELECT` clause. Aliasing works exactly as described in the chapter [Aliasing](../query-compilation/aliasing.md).

If the stream in `ON` was produced by an interleave `A#B`, the condition must use the output stream name:

```
RULE valid ON result WHEN result[0] > 0 DO DUMP -1 TO 0
```

A reference to a named interleave component is ambiguous and causes compilation to fail:

```
RULE invalid ON result WHEN A[0] > 0 DO DUMP -1 TO 0
```

The same rule applies when `#` is hidden in a substrate generated for a compound `FROM` expression.
