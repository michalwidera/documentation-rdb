# Type Promotion

What happens when we multiply data of type BYTE with data of type INTEGER? RetractorDB follows strict type-promotion rules. Multiplying a BYTE-type field by a value of a field that is of type INTEGER produces a schema field of type INTEGER. This happens at compile time.

At present, RetractorDB supports the following data types:

| Type     | Description                                   |
| -------- | --------------------------------------------- |
| BYTE     | values 0–255                                  |
| INTEGER  | 4-byte values for signed numbers              |
| UINT     | like INTEGER, for unsigned numbers            |
| RATIONAL | rational numbers                              |
| FLOAT    | floating-point numbers                        |
| DOUBLE   | double-precision floating-point numbers       |
| STRING   | character strings                             |

`STRING` and `RATIONAL` are used in descriptors, conversions, and expressions; their representation and behavior are checked by `ut_payload`, `ut_convertTypes`, and integration scenarios. Complex numbers and rational Eisenstein complex numbers remain outside the current set of types.

An example of type promotion in practice - the `scaled` query from the chapter [Underscore Symbol Processing](underscore-symbol-processing.md):

```rql
SELECT core0[_] * core1[_] STREAM scaled FROM core0 + core1
```

`core0` has fields BYTE and INTEGER, `core1` has fields INTEGER and FLOAT. After expanding `_`, the compiler determines the output fields' types:

| Expression          | Left type | Right type | Result type |
| ------------------- | -------- | --------- | ------------ |
| `scaled[0] * scaled[2]` | BYTE     | INTEGER   | INTEGER      |
| `scaled[1] * scaled[3]` | INTEGER  | FLOAT     | FLOAT        |

## Where the result field type comes from

The type, length, and multiplicity of a field are determined by a **single compiler pass** - `compiler::inferFieldShapes()` - which executes the field's reverse-Polish program on a stack of *types*, exactly the way `expressionEvaluator` executes it on a stack of *values*. The pass runs after field references and window aggregates have been resolved, and **before** expression simplification, so the descriptor does not depend on any optimizer switch.

Until September 2026 the same question was answered by four local rules, none of which saw the whole expression. The parser started from `INTEGER` and recognized `FLOAT` or `DOUBLE` only when the cast was the **last** token of the program; a separate pass inferred `STRING`; the window reduction type was settled somewhere else again. That produced three results inconsistent with the value the engine wrote into the field: `SELECT source[0]` over a `DOUBLE` field yielded `INTEGER`, `to_float('2.5') * 2` yielded `INTEGER`, and `to_integer(AVG(x : 10)) + 1` fell back to `RATIONAL`.

## Contract rules

A **pure field read** preserves the field's type and length. Reading one element of a numeric array yields a single value, so multiplicity drops to one; `STRING[N]` is a single slot and keeps its width.

A **binary operator** (`+`, `-`, `*`, `/`, `^`) yields the type that ranks higher in the order `BYTE < INTEGER < UINT < RATIONAL < FLOAT < DOUBLE` - with one exception: **`BYTE` with `BYTE` yields `INTEGER`**. This is not a design decision but a reflection of the language: `uint8_t + uint8_t` promotes to `int` in C++, and `int` is what ends up in the result. The same promotion applies to exact-type exponentiation, because `a^k` is computed by the same multiplication as the product written out.

A **unary operator** (`-x`, `NOT x`) preserves the argument's type - there is no promotion here.

**Comparisons** yield the operand type after normalization, without the `BYTE` promotion. They do not reach the `SELECT` list: they live in the `RULE` condition.

**Functions** share one policy:

| Functions                                                              | Result type         |
| ---------------------------------------------------------------------- | ------------------- |
| `isnull`, `IsZero`, `IsNonZero`, `Length`                              | always `INTEGER`    |
| `sin`, `cos`, `exp`                                                     | always `DOUBLE`; **rejected** over `RATIONAL` |
| `Sqrt`, `tan`, `log`, `log2`                                            | argument type; **rejected** over `RATIONAL` |
| `Ceil`, `Floor`, `round`, `trunc`                                       | argument type       |
| `Abs`, `null2zero`                                                     | argument type       |
| `to_integer`, `to_float`, `to_double`, `to_string`                     | target type         |

`sin`, `cos`, and `exp` compute in `double` and **return `DOUBLE`** even for integer arguments. The other mathematical functions compute through `double` and cast the result back to the argument's type: `Ceil` over a `DOUBLE` field yields `DOUBLE`, and `Sqrt` over `INTEGER` yields `INTEGER`. Explicit conversions determine the type of their result **also when they sit in the middle of an expression**: `to_float('2.5') * 2` is `FLOAT`, and `to_integer(AVG(x : 10)) + 1` is `INTEGER`.

Seven functions with an irrational range - `Sqrt`, `sin`, `cos`, `exp`, `tan`, `log` and `log2` - **do not compile** over an argument of type `RATIONAL`: the compiler rejects the plan and requires an explicit `to_double`. This matters in practice, because the reducers `MIN`, `MAX`, `AVG` and `SUMC` yield `RATIONAL` for integer or rational inputs. The reason, the error message, the reach of the gate (it also covers a `RULE ... WHEN` condition), and the exception for the rounding functions are described in [Field expressions and scalar functions](../query-language-construction/select-command/field-expressions-and-scalar-functions.md); they are not repeated here, so that the two pages cannot drift apart on the next change.

A **record-window aggregate** takes its type from the whole program of its argument, passed through the same rule as the stream reducers: an arithmetic source (`BYTE`, `INTEGER`, `UINT`, `RATIONAL`) reduces to `RATIONAL` so an average does not lose precision, while `FLOAT` and `DOUBLE` stay themselves. Hence `MIN(k : 4)` over an `INTEGER` field yields `RATIONAL`, but `MIN(to_double(k) : 4)` yields `DOUBLE`.

**`NULL` is not a type.** A field has a type, and a missing value is a marker in the record metadata. An expression that evaluates to `NULL` on a given record does not thereby change the type of its field. `null2zero(x)` passes the argument's type through, and the zero is stored in that very type.

## Propagation through the plan

Operators that **copy** the operand schema - `SELECT *`, the shift `>N`, decimation `-r`, the interleave `#`, the de-interleaves `&` and `%`, and the stream sum `+` - carry the producer's field shape slot by slot. The type travels through an arbitrarily long chain of intermediate streams.

Operators that **synthesize** a schema keep their own: the `MIN`/`MAX`/`AVG`/`SUMC` reducer in the `FROM` clause yields one field: `RATIONAL` for an integer or rational source, `FLOAT` for `FLOAT`, and `DOUBLE` for `DOUBLE`. The `@(step, width)` window yields fields of the widest type in the source record.

A `DECLARE` declaration is a contract with the source file and is **not subject to inference** - no compiler pass modifies it.

## Artifact format change

Correct typing changes `.desc` and the record layout wherever `INTEGER` used to come out: `DOUBLE` occupies 8 bytes instead of 4, so it shifts the offsets of the following fields. A stream computed by an older engine version has an artifact with a different layout and will be rejected at startup as an incompatible schema - just as after any other change to the field list. There is no compatibility period: the descriptor now describes what the engine actually writes, whereas before it described something else.
