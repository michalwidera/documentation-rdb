# Field Expressions and Scalar Functions

A field expression computes one value of an output record. It occurs in the `SELECT` list,
in a `RULE` condition, and as the argument of a record-history aggregate. Do not confuse it
with the stream expression in `FROM`, which constructs and schedules an entire stream.

## Building an expression

Operands are numeric and text literals, `$` inside a stream generator, field references,
and function results. A field may be addressed by name, stream-qualified name, or flat
index, for example `temperature`, `src.temperature`, and `src[0]`. For a numeric declaration
`a T[N]`, bare `a` denotes the complete array entry and is not a scalar operand; use
`a[0]`...`a[N-1]`. `STRING[N]` is one text field.

The basic arithmetic operators are `+`, `-`, `*`, `/`, and `^`. Parentheses change
grouping. `*` and `/` bind more strongly than `+` and `-`; exponentiation `^` binds most
strongly and is right-associative:

```rql
SELECT v*w^2, v^w^2, (v*w)^2 STREAM powers FROM source
```

These fields mean `v*(w^2)`, `v^(w^2)`, and `(v*w)^2`. A negative literal is one grammar
atom: `-2^2` means `(-2)^2`, while `-v^2` means `-(v^2)`.

For integer and rational types, a non-negative integral power has the semantics of repeated
multiplication, including type promotion and overflow. Other cases use floating-point
computation; an infinite or `NaN` result becomes NULL. Text operands are not allowed.

NULL propagates through ordinary arithmetic. Division by zero yields NULL for every numeric
type and does not stop later stream processing. Comparison and three-valued logic in a
`RULE` condition are documented in [Logical Condition](../rule-command-logical-condition.md).

> **⚠️ Warning** After an interleave `A#B`, do not refer to its components as `A[0]`,
> `A.field`, `A[_]`, or `A.*`. An interleave has one shared schema; use the output stream
> name or recover a component with `&` or `%`. See
> [Aliasing](../../query-compilation/aliasing.md).

## Available scalar functions

The sole name-and-arity list shared by the compiler and evaluator is the
`rqlFunctions.hpp` table. Matching is case-insensitive and the canonical spelling is stored
in the plan. An unknown function or invalid arity stops compilation rather than being
deferred to runtime.

| Group | Functions |
| ----- | --------- |
| Mathematical | `Sqrt`, `Ceil`, `Floor`, `Abs`, `round`, `trunc`, `sin`, `cos`, `exp`, `tan`, `log`, `log2` |
| Value handling | `isnull`, `null2zero`, `IsZero`, `IsNonZero`, `Length` |
| Conversions | `to_integer`, `to_float`, `to_double`, `to_string` |

Every function takes one expression argument. The only exception is the optional output
field width in `to_string(expression : width)`.

### Predicates and missing values

- `isnull(x)` returns 1 for NULL and 0 for a present value;
- `null2zero(x)` maps NULL to integer zero but passes a present value without changing its
  type;
- `IsZero(x)` and `IsNonZero(x)` return integer 1 or 0 for a numeric argument.

`null2zero` is lossy: afterwards, an original missing value cannot be distinguished from an
actual zero. It does not replace the NULL bitmap stored in `.meta`.

### String length

`Length(x)` accepts a string only. It counts the actual value up to the first zero byte, not
the declared `STRING[N]` width. A `STRING[8]` field containing `alpha` therefore yields 5.
A numeric argument is a runtime error.

### Conversions

`to_integer`, `to_float`, and `to_double` convert a numeric or textual value to the named
type. NULL passes through unchanged. `to_integer` truncates toward zero rather than flooring:
`to_integer(-8/3)` yields `-2`.

`to_string` creates a text field. Without a second part its width is 32 bytes;
`to_string(x : N)` declares N bytes. The separator is a colon because a comma separates
fields in the `SELECT` list:

```rql
SELECT to_string(value : 10), Length(label), null2zero(optional) \
STREAM converted FROM source
```

The output text width is inferred after field references have been resolved, so a pure copy
of `STRING[N]` and text concatenation retain the correct descriptor. The type of the whole
expression, including numeric expressions, is determined by `compiler::inferFieldShapes()` after
field references are resolved; see [Type Promotion](../../query-compilation/type-promotion.md).

The declared width is a property of the **field**, not a side effect of one particular
compilation pass. It also holds when the whole argument is constant: `to_string(42 : 16)` yields
`STRING[16]`, not `STRING[2]`. Expression simplification folds the argument underneath the call
but never removes `to_string` itself — otherwise the declaration would disappear together with
the program on a **second** compilation of the plan, that is after an ad-hoc query (`xqry -a`),
which compiles the live plan a second time.

### `sin`, `cos`, and `exp`

All three functions take a numeric argument and return `DOUBLE`, regardless of the argument's
type. `sin` and `cos` interpret angles in **radians**. For an `INTEGER` field `k`, the expressions
`sin(k)`, `cos(k)`, and `exp(k)` therefore produce `DOUBLE` fields without truncating fractional
results. A `NULL` argument yields `NULL`; a non-finite result, such as `exp(1000)`, also yields
`NULL` without stopping the stream.

A `RATIONAL` argument is the exception: the compiler **rejects** it and requires an explicit
`to_double`, exactly as it does for `Sqrt` — see the section below.

Changing the result type of `sin` and `cos` can change the `.desc` descriptor and record layout
relative to an older engine: `INTEGER` and `FLOAT` occupy 4 bytes, while `DOUBLE` occupies 8.
An existing artifact with the old schema must be recreated or written to a separate output stream.

### Irrational functions over a RATIONAL value

`Sqrt`, `sin`, `cos`, `exp`, `tan`, `log`, and `log2` do **not accept** a `RATIONAL` argument —
the compiler rejects such a query through the `Check result:` channel and names the workaround.
In practice this concerns stream reducers, because `MIN`/`MAX`/`AVG`/`SUMC` always produce
`RATIONAL`:

```rql
SELECT * STREAM m FROM AVG(src)
SELECT Sqrt(m[0]) STREAM o FROM m              // rejected at compilation
SELECT Sqrt(to_double(m[0])) STREAM o FROM m   // correct
```

One rule applies: **a function with an irrational range over an exact rational value requires
an explicit `to_double`**. The same rule covers a rule condition (`RULE ... WHEN`), which the
compiler checks in a separate pass.

For `Sqrt`, `tan`, `log`, and `log2` the reason is not a loss of precision but a silent **wrong
value**. These four are computed through `double` and cast back to the argument type, and the
return path to `RATIONAL` approximates the result with a fraction of a very large denominator
(`Sqrt(2)` yields `19601/13860`, `log(2)` yields `2731/3940`). `RATIONAL` stores numerator and
denominator in 32 bits with no range check, so two further multiplications overflow it:
`Sqrt(x)*Sqrt(x)*Sqrt(x)` returned `-4.247` instead of `+2.828` — with the wrong sign and no
error at all.

For `sin`, `cos`, and `exp` the reason is different: these three end at `DOUBLE` and never
return to `RATIONAL`, so they would compute correctly. Their rejection is a **language contract
decision**, made so that no list of exceptions has to be remembered — one rule instead of seven
separate behaviours. The price is a `to_double` in every query computing, say, an RMS over
a reducer.

The restriction extends neither to the remaining functions nor to other argument types. The
rounding functions `Floor`, `Ceil`, `round`, and `trunc` over `RATIONAL` are safe, because their
result is integral and therefore has denominator 1, and `Abs` operates on the value directly and
never touches the denominator.

The gate covers **only** the pairing with `RATIONAL` and changes no function's result type.
`tan`, `log`, and `log2` over `INTEGER` still yield `INTEGER`, that is, they truncate the
fractional part — an explicit and intended loss, not an overflow. Bringing them to `DOUBLE`, as
`sin`, `cos`, and `exp` are, would change the field type in `.desc`, so it is a separate task.

> **_NOTE:_** Functions and type propagation are covered by the integration tests
> `fncall_runtime_case`, `string_field_passthrough`, `issue121_isnull`,
> `issue128_numeric_to_string`, and `issue128_string_to_numeric`, and by the `ut_compiler`,
> `ut_expeval`, and `ut_facctxtsrc` unit tests.
