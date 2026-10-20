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

A single comparison has two scalar operands. Chains such as `0 < measurements[0] < 10`, `0 <= measurements[0] < 10`, or `measurements[0] = 1 = 1` are syntax errors; the parser identifies the second comparison operator. Express a range as two comparisons joined by `AND`:

```rql
RULE in_range ON measurements WHEN 0 < measurements[0] AND measurements[0] < 10 DO DUMP -1 TO 0
```

Comparison chains have been rejected since fix #555. The earlier parser accepted them and used a comparison's result as an operand of another comparison; this did not check the intended range.

## Logical connectives

| Operator | Meaning |
| -------- | ------- |
| `AND`    | conjunction - both conditions must be satisfied |
| `OR`     | disjunction - one condition is enough            |
| `NOT`    | negation - the condition must not be satisfied   |

Precedence in `WHEN`, from highest to lowest, is arithmetic, comparison, `NOT`, `AND`, `OR`. `NOT measurements[0] < 0` negates the entire comparison `measurements[0] < 0`; for a non-NULL value, the condition is true when the field is non-negative. In `NOT measurements[0] < 0 AND measurements[0] > 5`, negation applies to the first comparison, and `AND` joins the two conditions. `AND` binds more strongly than `OR`.

Since fix #555, `NOT` belongs exclusively to the `WHEN` condition. It cannot be used as a field operator in `SELECT` or inside arithmetic, for example `measurements[0] + NOT measurements[0]`. Previously, `NOT measurements[0] < 0` negated the field alone and then compared the result with zero, so the condition was never true.

The grammar does not support parentheses around logical conditions or comparisons. Parentheses may group arithmetic expressions on either side of a comparison, for example `(measurements[0]+1) < 10`. Write compound conditions according to the precedence above.

A bare `STRING` field is true when its value is nonempty. String comparisons and `NOT` over a string return `INTEGER` 1 or 0. `AND` and `OR` use the left operand's type, or the right operand's type if the left is `NULL`; a result based on a string is `INTEGER`. Thus `WHEN NOT status[0]` is true for an empty string, and a false string comparison does not trigger a rule through `OR`. `NULL` still follows the condition's three-valued logic.

## Expression structure

A condition is built from the fields of the stream schema specified in the `ON` clause. Fields are identified the same way as in `SELECT` - by the stream name with an index:

```rql
WHEN stream[index] operator value
```

Compound conditions are joined with connectives:

```rql
WHEN stream[0] > 10 AND stream[1] != 0
WHEN stream[0] = 5 OR stream[0] = 7
WHEN NOT stream[0] < 0
```

## Examples

```rql
RULE high_alarm \
ON measurements \
WHEN measurements[0] > 100 OR measurements[0] < -100 \
DO DUMP -10 TO 10 RETENTION 50

RULE signaling \
ON status \
WHEN status[0] = 1 AND status[1] != 0 \
DO SYSTEM 'systemctl restart sensor-reader'

RULE one_time ON data WHEN NOT data[0] = 0 DO DUMP -5 TO 0
```

## Field access

The condition refers to the fields of the stream specified in `ON`. The field index corresponds to its position in that stream's schema - the same as in the `SELECT` clause. The condition reads the stream's output record, so an index equal to or greater than its field count is a compilation error (see [Index out of range](../query-compilation/aliasing.md#index-out-of-range)). Aliasing works exactly as described in the chapter [Aliasing](../query-compilation/aliasing.md).

If the stream in `ON` was produced by an interleave `A#B`, the condition must use the output stream name:

```rql
RULE valid ON result WHEN result[0] > 0 DO DUMP -1 TO 0
```

A reference to a named interleave component is ambiguous and causes compilation to fail:

```rql
RULE invalid ON result WHEN A[0] > 0 DO DUMP -1 TO 0
```

The same rule applies when `#` is hidden in a substrate generated for a compound `FROM` expression.
