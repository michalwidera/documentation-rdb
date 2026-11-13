# Syntax and Compilation Errors

An invalid query may be rejected during syntax recognition, numeric validation, or plan construction. This chapter explains the diagnostics reported by the parser and compiler and shows how to correct the query. It also covers constructs that conform to the grammar but cannot be executed by the engine, such as a history window without a data source.

The unit/integration test map and the way requirement identifiers are linked are described in the [Integration Tests appendix](../appendices/integration-tests.md#requirements-in-code-and-test-traceability).

Go to the group that matches the diagnostic:

- [Statement Syntax, Comments, and Parentheses](#statement-syntax-comments-and-parentheses)
- [Numbers, Intervals, and Dimensions](#numbers-intervals-and-dimensions)
- [Stream Names, Fields, and Dependencies](#stream-names-fields-and-dependencies)
- [Stream Operators and Functions](#stream-operators-and-functions)
- [History Windows in the SELECT List](#history-windows-in-the-select-list)
- [LET, VAR, and DO SET](#let-var-and-do-set)
- [Stream-Family Generators](#stream-family-generators)
- [RULE Statements](#rule-statements)
- [Sources, Storage, and Directives](#sources-storage-and-directives)
- [Ad Hoc and Plan Reload Refusals](#ad-hoc-and-plan-reload-refusals)

## Reading a Diagnostic

First, check the file without starting data processing:

```bash
xretractor -c zapytania.rql 2>bledy.txt
echo $?
cat bledy.txt
```

Exit code `0` means compilation succeeded. Rejection of an invalid plan returns `EPROTO`, which is `71` on Linux. Other failures, such as a missing `.rql` file, may return a different code; scripts should always check for any nonzero result. The `-c` mode does not start sources or check the availability of data files.

| Diagnostic element | Meaning | What to check |
| --- | --- | --- |
| `Syntax error @Rql`, `line:L:C at ...`, `msg:...` | The lexer or parser did not recognize the syntax. | The indicated character, preceding word, comma, single quote, or parenthesis. |
| `Parse result:...` | Parsing or a semantic check performed by the parser failed. | In addition to syntax, check numeric ranges, `DECLARE` options, directives, `LET`/`VAR` declarations, and the `RULE` target. |
| `Check result:...` | The parser accepted the syntax, but the compiler refused to construct the plan. | Field names and indices, dependencies, types, operator compatibility, and history resources. |
| `FATAL: internal compiler error: ...` | An internal compiler invariant was violated. | Keep the plan, diagnostic, and program version for a bug report. This diagnostic does not identify an ordinary syntax correction. |

Line number `L` starts at `1`, and position `C` within the line starts at `0`. For a statement continued with `\`, the line number identifies the start of the joined statement, and the position refers to the joined text. `Input file:` identifies the file being rejected. Correct the first error and compile again: later checks may reveal further problems only after the first one has been resolved.

The parser prints details to stderr and then returns a shortened status, such as `Parse result:line 3:9 ...`. These are two representations of the same refusal. `at <EOF>` identifies the end of the submitted statement, while `at <unknown>` can occur on a lexer error before a token exists. The syntax-error status is a single line limited to 300 bytes; the full `msg:` text remains on the server's stderr. Not every semantic refusal includes a position: it may appear as `Error: ...` and `Parse result:...`.

The tables below quote characteristic **diagnostic fragments**. The full message also includes stream names, values, and sometimes a position in the file. The list of tokens expected by the parser depends on where the error occurs.

## Shared Sources for the Examples

Check each table pair and each block marked "Incorrect" or "Correct" **separately**, appending it to the declarations below. Blocks marked "complete plan" are the exception: they already contain all required declarations. The source filenames are examples: they are sufficient for checking with `-c`, but execution requires data matching the declared schemas.

```rql
DECLARE v INTEGER, w INTEGER STREAM src, 1 TEXTFILE 'dane.txt'
DECLARE z INTEGER STREAM aux, 1 TEXTFILE 'pomocnicze.txt'
DECLARE a INTEGER[3] STREAM vec, 1 BINFILE 'wektor.bin'
DECLARE label STRING[8] STREAM words, 1 BINFILE 'napisy.bin'
SELECT * STREAM out FROM src VOLATILE
```

`src` has two fields, `aux` has one, and `vec` has three numeric elements. `words` contains one string eight bytes long. Element indices start at zero. `out` is a `SELECT` result to which rules can be attached.

## Statement Syntax, Comments, and Parentheses

`mismatched input` means a token does not fit at that position, `missing` identifies a required token that is absent, `extraneous input` identifies an extra token, and `token recognition error` identifies a character the lexer cannot recognize. A single error does not necessarily produce all these messages. Also check the text before the reported position: the parser often detects a missing comma or parenthesis only when it reaches the next word.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `missing STREAM` | `SELECT v result FROM src` | `SELECT v STREAM result FROM src` |
| `missing ','` | `DECLARE x INTEGER STREAM sensor 1 TEXTFILE 'x.txt'` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'` |
| `no viable alternative` | `SELECT to_string(v,16) STREAM result FROM src` | `SELECT to_string(v:16) STREAM result FROM src` |
| `expecting ID` | `SELECT v STREAM MIN FROM src` | `SELECT v STREAM minimum FROM src` |
| `extraneous input ';'` | `SELECT v STREAM result FROM src;` | `SELECT v STREAM result FROM src` |
| `token recognition error` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE "x.txt"` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'` |
| `which is not defined in the plan` | `SELECT v STREAM result FROM src # komentarz` | `SELECT v STREAM result FROM src // komentarz` |

In `to_string`, a colon separates the output field width; commas separate items in the `SELECT` list. Keywords, including `MIN`, `MAX`, `AVG`, `SUMC`, `TIMEOUT`, and `RATIONAL`, cannot be used as identifiers in spellings recognized by the grammar. A semicolon is not an RQL statement terminator. Strings use single quotes. `#` starts a comment only when it is the first non-whitespace character on a line; in `FROM`, it is the interleave operator. A single word after `#` may therefore be accepted as the name of a second stream and cause a compilation error, whereas a longer comment may cause a syntax error.

By default, each physical line is a separate statement. Moving `FROM` to the next line requires a continuation character:

**Incorrect:**

```rql
SELECT v STREAM result
FROM src
```

**Correct:**

```rql
SELECT v STREAM result \
FROM src
```

A comparison in `RULE WHEN` has two operands. Expressing a range requires `AND`; `NOT` belongs to `WHEN` logic and is not an operator in a scalar `SELECT` expression. Parentheses group arithmetic, but the grammar does not allow complete comparisons or logical conditions inside them.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `mismatched input '<'` | `RULE alarm ON out WHEN 0 < out[0] < 10 DO DUMP -1 TO 1` | `RULE alarm ON out WHEN 0 < out[0] AND out[0] < 10 DO DUMP -1 TO 1` |
| `missing ')'` | `RULE alarm ON out WHEN (out[0] > 0) DO DUMP -1 TO 1` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -1 TO 1` |
| `'NOT'` | `SELECT NOT v STREAM result FROM src` | `SELECT IsZero(v) STREAM result FROM src` |

The final correction tests for zero in an output field. If you need to negate a compound condition, write it in a rule, following the [logical condition rules](rule-command-logical-condition.md).

**Tests and requirements:** [Syntax, Comments, and Error Positions](../appendices/integration-tests.md#rql-tests-syntax).

## Numbers, Intervals, and Dimensions

### Out-of-Range Number or Invalid Interval

A literal must fit the type in which the parser reads it. A later cast cannot repair a literal that has already been rejected. An interval fraction cannot have a zero denominator, and the source interval and arguments of the `&`, `%`, and `-` operators must be positive. In these positions, decimal notation is converted to a rational representation with limited range and resolution.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `numeric literal 2147483648 is out of range` | `SELECT v+2147483648 STREAM result FROM src` | `SELECT v+2147483647 STREAM result FROM src` |
| `fraction 1/0 has a zero denominator` | `DECLARE x INTEGER STREAM sensor, 1/0 TEXTFILE 'x.txt'` | `DECLARE x INTEGER STREAM sensor, 1/10 TEXTFILE 'x.txt'` |
| `interval 0 must be greater than zero` | `DECLARE x INTEGER STREAM sensor, 0 TEXTFILE 'x.txt'` | `DECLARE x INTEGER STREAM sensor, 1/10 TEXTFILE 'x.txt'` |
| `numeric literal 0.00000001 is out of range` | `DECLARE x INTEGER STREAM sensor, 0.00000001 TEXTFILE 'x.txt'` | `DECLARE x INTEGER STREAM sensor, 1/100000000 TEXTFILE 'x.txt'` |

The first correction changes the value to one that fits `INTEGER`. If the application needs a larger number, declare it as a constant of an appropriate type, for example `LET OFFSET : DOUBLE = 2147483648`, and use `?OFFSET`; simply wrapping an invalid literal in `to_double` does not make it valid.

### Zero Size or Exceeded Limit

`must be greater than zero`, `must not be negative`, and `exceeds the limit` describe a constraint on a specific argument. Field length, `to_string` width, window step, and absolute window width must be positive. A shift of `>0` is allowed. A negative AGSE window width specifies its direction and is valid as long as its absolute value is within the limit.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `must be greater than zero` | `DECLARE x INTEGER[0] STREAM sensor, 1 BINFILE 'x.bin'` | `DECLARE x INTEGER[3] STREAM sensor, 1 BINFILE 'x.bin'` |
| `must be greater than zero` | `SELECT * STREAM result FROM src@(0,3)` | `SELECT * STREAM result FROM src@(1,3)` |
| `must be greater than zero` | `SELECT * STREAM result FROM src@(1,0)` | `SELECT * STREAM result FROM src@(1,3)` |
| `must be greater than zero` | `SELECT MIN(src[0]:0) STREAM result FROM src` | `SELECT MIN(src[0]:3) STREAM result FROM src` |
| `must be greater than zero` | `SELECT to_string(v:0) STREAM result FROM src` | `SELECT to_string(v:16) STREAM result FROM src` |
| `exceeds the limit 65536` | `SELECT * STREAM result FROM src>65537` | `SELECT * STREAM result FROM src>10` |

The complete limit table and an explanation of aggregate constraints are in [Plan Size Limits](../query-compilation/plan-size-limits.md). The compiler also checks calculated quantities, such as concatenated string length, record size, total plan element count, logical origin, and startup latency. Arguments that individually fit their limits do not guarantee that the entire plan will fit.

For example, two `to_string` fields of width `40000` are individually valid, but concatenating them produces one string of length `80000`, exceeding the field limit:

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `has length 80000; the limit is 65536` | `SELECT to_string(v:40000)+to_string(w:40000) STREAM result FROM src` | `SELECT to_string(v:16)+to_string(w:16) STREAM result FROM src` |

`has a startup latency of ... slots; the limit is 2147483647` means that the plan's computed tail exceeds its representable range, including for interleave `#`. It is not a compilation timeout or a `DEVICE` read deadline. Reduce windows or shifts and check the source-interval relationships; individual operators fitting their limits is insufficient.

The logical origin calculated for a compound plan must fit in `int`. Two consecutive AGSE windows `@(1,65536)` over a single-field source exceed the limit of `2147483647` slots. The diagnostic contains `has a logical origin of ... slots; the limit is ...`. The correction reduces both window widths:

**Incorrect (complete plan):**

```rql
DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'
SELECT * STREAM first FROM sensor@(1,65536)
SELECT * STREAM result FROM first@(1,65536)
```

**Correct (complete plan):**

```rql
DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'
SELECT * STREAM first FROM sensor@(1,32)
SELECT * STREAM result FROM first@(1,32)
```

**Tests and requirements:** [Numbers, Intervals, and Limits](../appendices/integration-tests.md#rql-tests-numbers).

## Stream Names, Fields, and Dependencies

### Unknown Name or Index Outside the Record

A missing stream in `FROM`, a missing field in a schema, and an out-of-range index are three different causes. Index `src[2]` is invalid because `src` has two positions: `0` and `1`. The array name `a` alone does not identify a single element. Read a numeric array using `a[0]`, `a[1]`, and so on, or use a flat stream index.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `which is not defined in the plan` | `SELECT * STREAM result FROM missing` | `SELECT * STREAM result FROM src` |
| `OUT_OF_BUSSINESS is reserved stream name` | `SELECT * STREAM OUT_OF_BUSSINESS FROM src` | `SELECT * STREAM result FROM src` |
| `has no field` | `SELECT src.temperature STREAM result FROM src` | `SELECT src.v STREAM result FROM src` |
| `out of range` | `SELECT src[2] STREAM result FROM src` | `SELECT src[1] STREAM result FROM src` |
| `not a single field` | `SELECT a STREAM result FROM vec` | `SELECT a[0] STREAM result FROM vec` |
| `out of range` | `SELECT a[3] STREAM result FROM vec` | `SELECT a[2] STREAM result FROM vec` |
| `which is not in its FROM clause` | `SELECT aux[0] STREAM result FROM src` | `SELECT aux[0] STREAM result FROM aux` |
| `contributes no contiguous block of fields` | `SELECT aux[_] STREAM result FROM src` | `SELECT aux[_] STREAM result FROM aux` |

The field list does not retrieve arbitrary other streams from the plan. It reads the input record determined by `FROM`. To use fields from two sources together, construct the appropriate expression in `FROM`, such as a stream sum, and refer to its fields.

An ordinary `SELECT` may refer to a producer defined later in the file if the entire plan is acyclic. Reordering declarations alone does not fix a typo or a cycle. Different ordering rules apply to `LET`, `VAR`, and attaching a `RULE`: their declarations or target must already be known to the parser.

### Reading a Constituent After Interleaving

The diagnostic `constituent of an interleave (#)` means an attempt to read a named constituent through the `#` operator. An interleave has one shared schema; `src[0]` does not identify only records originating from `src`. This also applies to `src.v`, `src[_]`, `src.*`, and field names resolved as fields of a constituent.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `constituent of an interleave (#)` | `SELECT src[0] STREAM result FROM src#out` | `SELECT result[0] STREAM result FROM src#out` |

The correct variant reads the first position of the shared input record. If the goal is to recover a specific constituent, use de-interleave `&` or `%` with the appropriate interval, rather than merely replacing the name without considering the intended computation. See [interleaving](select-command/interleaving-sequencing.md) and [aliasing](../query-compilation/aliasing.md) for the rules.

### Self-Reference and Cycles

`a stream cannot be its own producer` means a stream directly reads its own result in `FROM`. `Circular dependency in stream definitions` means the dependencies prevent interval resolution. In a correctly parsed plan, remove the cycle rather than merely reordering the lines.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `a stream cannot be its own producer` | `SELECT * STREAM result FROM result` | `SELECT * STREAM result FROM src` |

**Incorrect:**

```rql
SELECT * STREAM first FROM second
SELECT * STREAM second FROM first
```

**Correct:**

```rql
SELECT * STREAM first FROM second
SELECT * STREAM second FROM src
```

In the corrected pair, producer `second` still appears after its consumer, but the dependency ends at source `src`. See [Loop Detection in Compilation](../query-compilation/loop-detection.md).

**Tests and requirements:** [References, Indices, Interleaving, and Cycles](../appendices/integration-tests.md#rql-tests-references).

## Stream Operators and Functions

### Interleave Schemas and the Difference Interval

`Hash operation needs same schemas on arguments stream` or `HASH operation constraint failed` indicates a mismatch in the number of flat elements in the arguments of `#`. Field counts must match; the compiler reconciles types and widths at corresponding positions. In this example, two-field `src` cannot be directly interleaved with single-field `aux`. First, select the required position:

**Incorrect:**

```rql
SELECT * STREAM result FROM src#aux
```

**Correct:**

```rql
SELECT src[0] STREAM scalar FROM src
SELECT * STREAM result FROM scalar#aux
```

`SUBTRACT interval constraint failed` means the difference operator was given a target interval shorter than the source interval. The `-` operator in `FROM` selects records at a slower or equal rate; it does not speed up a stream.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `SUBTRACT interval constraint failed` | `SELECT * STREAM result FROM src-1/2` | `SELECT * STREAM result FROM src-2` |

`src` has interval `1`, so the corrected target `2` is valid. Choose the value to match the rate required by the application.

### Invalid De-interleave or Unrepresentable Computed Interval

The `&` and `%` operators refuse an argument equal to the source interval: the result-interval formula would have a zero denominator. `You cannot make faster div from slower source` or `You cannot make faster mod from slower source` means that the computed result would be faster than the source. Check the complete de-interleave formula, as well as whether the argument is positive.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `'&' argument equal to the source interval` | `SELECT * STREAM result FROM src&1` | `SELECT * STREAM result FROM src&2` |
| `'%' argument equal to the source interval` | `SELECT * STREAM result FROM src%1` | `SELECT * STREAM result FROM src%2` |
| `You cannot make faster div from slower source` | `SELECT * STREAM result FROM src&1/4` | `SELECT * STREAM result FROM src&2` |
| `You cannot make faster mod from slower source` | `SELECT * STREAM result FROM src%1/4` | `SELECT * STREAM result FROM src%2` |

`Stream interval out of representable range - simplify the plan or use coarser intervals` concerns an interval **computed by the compiler**. Each argument may be valid individually while the result does not fit the rational representation. Refused example (complete plan):

```rql
DECLARE x INTEGER STREAM sensor, 46341/46339 TEXTFILE 'x.txt'
SELECT * STREAM result FROM sensor&46342/46339
```

Simplify the expression or choose different intervals consistent with the required cadence; rounding changes the computation. See [Interval Resolution](../query-compilation/interval-resolution.md) for the formulas.

### Unknown Function or Wrong Call Form

The compiler also checks function names in rule conditions and `DO SET`. A width after a colon in an ordinary function call is available only for `to_string`. A stream reducer and a record-history window aggregate take different arguments: `MIN(src)` belongs in `FROM`, whereas `MIN(src[0]:3)` belongs in the field list.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `not a known RQL function` | `SELECT Sqrtt(v) STREAM result FROM src` | `SELECT Sqrt(v) STREAM result FROM src` |
| `takes no width argument` | `SELECT Sqrt(v:16) STREAM result FROM src` | `SELECT Sqrt(v) STREAM result FROM src` |
| `expecting ':'` | `SELECT MIN(src) STREAM result FROM src` | `SELECT MIN(src[0]:3) STREAM result FROM src` |

In the last row, the correction aggregates three historical records of one field. If the intention is to reduce the fields of the current record, put the reducer in `FROM`. The compiler rejects using the bare word `MIN` as a field with `reads the result of stream reducer ... directly`. First, create a stream containing the reduction result:

**Incorrect:**

```rql
SELECT MIN STREAM result FROM MIN(src)
```

**Correct:**

```rql
SELECT * STREAM reduced FROM MIN(src)
SELECT reduced[0] STREAM result FROM reduced
```

### Unsupported Argument Type

Not every function or operation accepts every type. Unary `-` does not accept `STRING`, and `~` accepts only `BYTE` or `UINT`. Functions `Sqrt`, `sin`, `cos`, `exp`, `tan`, `log`, and `log2` reject a `RATIONAL` argument; an explicit conversion to an approximate type is required. This also applies to stream reducer results, which are `RATIONAL` for integer arguments.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `unary '-' is not defined for STRING` | `SELECT -label STREAM result FROM words` | `SELECT -to_double(label) STREAM result FROM words` |
| `is defined only for BYTE and UINT` | `SELECT ~v STREAM result FROM src` | `SELECT -v STREAM result FROM src` |

The first correction makes sense when the string represents a number; a failed value conversion produces `NULL` at runtime. The second performs arithmetic negation of an integer. If the intention is a bitwise complement, the source or operand must have type `BYTE` or `UINT`.

**Incorrect:**

```rql
SELECT * STREAM reduced FROM AVG(src)
SELECT Sqrt(reduced[0]) STREAM result FROM reduced
```

**Correct:**

```rql
SELECT * STREAM reduced FROM AVG(src)
SELECT Sqrt(to_double(reduced[0])) STREAM result FROM reduced
```

Here, the diagnostic fragment is `'Sqrt' over a RATIONAL value is not implemented`. The conversion deliberately moves from an exact value to an approximate one. For the function list and type rules, see [Field Expressions and Scalar Functions](select-command/field-expressions-and-scalar-functions.md).

**Tests and requirements:** [Functions and Operand Types](../appendices/integration-tests.md#rql-tests-functions).

## History Windows in the SELECT List

The aggregate `MIN/MAX/AVG/SUMC(expression:N)` reads the history of one stream. `FROM` must therefore be a single stream reference, and the argument must read at least one numeric field from that stream. You cannot aggregate constants alone or strings, or nest one window aggregate inside another.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `reads no field` | `SELECT AVG(1:3) STREAM result FROM src` | `SELECT AVG(src[0]:3) STREAM result FROM src` |
| `window aggregates are arithmetic` | `SELECT AVG(label:3) STREAM result FROM words` | `SELECT AVG(to_double(src[0]):3) STREAM result FROM src` |

The second correction selects a numeric source. If numeric data arrives as text, first create a separate stream that performs the conversion, then aggregate its result.

### Window Over a Compound FROM

The diagnostic `its FROM clause must be a single stream reference` requires moving the stream transformation into a separate query. If you need a window over a sum of sources, first create a stream from that sum, then read its history.

**Incorrect:**

```rql
SELECT AVG(src[0]:3) STREAM result FROM src+aux
```

**Correct:**

```rql
SELECT * STREAM joined FROM src+aux
SELECT AVG(joined[0]:3) STREAM result FROM joined
```

### Nested Windows

The diagnostic `nests one window aggregate inside another` means the inner results do not yet have their own history. Create a separate stream for them:

**Incorrect:**

```rql
SELECT AVG(MIN(src[0]:3):4) STREAM result FROM src
```

**Correct:**

```rql
SELECT MIN(src[0]:3) STREAM minima FROM src
SELECT AVG(minima[0]:4) STREAM result FROM minima
```

### Window in a Rule or DO SET

`uses a window aggregate in a RULE condition` and `uses a window aggregate in DO SET` identify an unsupported location for aggregation. A rule uses the completed stream record. First, calculate the aggregate in `SELECT`, then let the rule read the resulting field:

**Incorrect:**

```rql
RULE alarm ON out WHEN AVG(out[0]:3) > 10 DO DUMP -1 TO 1
```

**Correct:**

```rql
SELECT AVG(src[0]:3) STREAM mean FROM src
RULE alarm ON mean WHEN mean[0] > 10 DO DUMP -1 TO 1
```

The same approach applies to a value assigned by `DO SET`. In addition, a `VAR` variable cannot occur inside a window argument: it changes at runtime, and the history stores source records, not past values of the variable. See [Aggregate Operators](select-command/aggregate-operators.md) for the complete rules.

**Tests and requirements:** [History Windows](../appendices/integration-tests.md#rql-tests-windows).

## LET, VAR, and DO SET

### Use Before Declaration, Constant Names, and Types

`LET` and `VAR` names share a case-sensitive namespace. A reference takes the form `?N`, without a space after `?`. The declaration must precede the first use and cannot be repeated. A name cannot contain `$`. The right-hand side of a declaration is a single numeric literal, not an arithmetic expression.

**Incorrect (complete plan):**

```rql
DECLARE x INTEGER[?N] STREAM sensor, 1 BINFILE 'x.bin'
LET N = 3
```

**Correct (complete plan):**

```rql
LET N = 3
DECLARE x INTEGER[?N] STREAM sensor, 1 BINFILE 'x.bin'
```

The cause is identified by `is not declared; LET must precede its first use`. The diagnostic `is already declared` requires removing the second declaration or giving it a different name. Declaring a `VAR` with a name already used by a `LET` is also a duplicate.

**Incorrect:**

```rql
LET N = 3
VAR N = 0
```

**Correct:**

```rql
LET N = 3
VAR COUNT = 0
```

### Constant in the Wrong Context

Array sizes, field indices, and window widths require integer values. With a type annotation, these contexts accept `INTEGER`. Intervals accept constants without an annotation or annotated as `INTEGER` or `RATIONAL`. An unannotated `LET` fraction may define an interval, but it has no direct literal form in a scalar expression; use `: RATIONAL` for an exact value in a field.

**Incorrect:**

```rql
LET SCALE = 1/2
SELECT src[0]*?SCALE STREAM result FROM src
```

**Correct:**

```rql
LET SCALE : RATIONAL = 1/2
SELECT src[0]*?SCALE STREAM result FROM src
```

Diagnostic fragment: `is a fraction, which an expression has no literal for`. Other rejections in this group include `is not an integer`, `cannot be used in ...`, and `is out of range for ...`. Type `INTEGER` cannot accept `1.5`; conversion of a declaration literal to an integer type must be exact. Types `BYTE` and `STRING` are not valid annotations for `LET` or `VAR`.

Example of `is not an integer` for a window width:

**Incorrect:**

```rql
LET N = 1.5
SELECT AVG(src[0]:?N) STREAM result FROM src
```

**Correct:**

```rql
LET N : INTEGER = 3
SELECT AVG(src[0]:?N) STREAM result FROM src
```

### Variable Used to Define Plan Structure

`variable ?N cannot be used in ...` means a runtime variable is being used as a parameter that must be fixed during compilation, such as a window width, family size, or interval. If the value defines structure, declare a constant:

**Incorrect:**

```rql
VAR N = 3
SELECT AVG(src[0]:?N) STREAM result FROM src
```

**Correct:**

```rql
LET N = 3
SELECT AVG(src[0]:?N) STREAM result FROM src
```

### Invalid Assignment Target or Type

The target of `DO SET` must be a declared `VAR` variable. Attempting to modify a `LET` produces `cannot be the target of DO SET`; an unknown name produces `VAR must precede its first use`.

**Incorrect:**

```rql
LET COUNT = 0
RULE increase ON out WHEN out[0] > 0 DO SET ?COUNT = ?COUNT+1
```

**Correct:**

```rql
VAR COUNT = 0
RULE increase ON out WHEN out[0] > 0 DO SET ?COUNT = ?COUNT+1
```

A compound expression on the right-hand side must have the same type as the variable. The diagnostic `no implicit conversion` requires an explicit cast or a change to the declared type. A standalone literal or a reference to a `LET` constant may be converted to the target type if the value is representable; this does not imply automatic conversion of arbitrary expressions.

**Incorrect:**

```rql
VAR LEVEL = 0
RULE update ON out WHEN out[0] > 0 DO SET ?LEVEL = to_double(out[0])+0.5
```

**Correct:**

```rql
VAR LEVEL : DOUBLE = 0
RULE update ON out WHEN out[0] > 0 DO SET ?LEVEL = to_double(out[0])+0.5
```

The correction preserves the fractional part by changing the variable type to `DOUBLE`. If the application needs an integer, you can instead explicitly apply `to_integer` to the entire expression, accounting for truncation of the fractional part. See [LET](let-command.md) and [VAR and DO SET](var-command.md).

**Tests and requirements:** [LET Constants and Type Annotations](../appendices/integration-tests.md#rql-tests-constants); [VAR Variables and DO SET Assignments](../appendices/integration-tests.md#rql-tests-variables).

## Stream-Family Generators

A family `STREAM cell[N]` expands into `N` streams. `$` denotes the instance ordinal and is meaningful only inside a generator. The size must be positive, the template must use `$`, and all expanded indices must fit the source.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `uses '$' outside a stream generator` | `SELECT $ STREAM result FROM vec` | `SELECT $ STREAM cell[3] FROM vec` |
| `uses no '$'` | `SELECT vec[0] STREAM cell[3] FROM vec` | `SELECT vec[$] STREAM cell[3] FROM vec` |
| `must be greater than zero` | `SELECT vec[$] STREAM cell[0] FROM vec` | `SELECT vec[$] STREAM cell[3] FROM vec` |
| `out of range` | `SELECT vec[$] STREAM cell[4] FROM vec` | `SELECT vec[$] STREAM cell[3] FROM vec` |
| `must not carry a FILE directive` | `SELECT vec[$] STREAM cell[3] FROM vec FILE 'wspolny.bin'` | `SELECT vec[$] STREAM cell[3] FROM vec` |
| `is not a stream generator` | `SELECT * STREAM result FROM src[0]` | `SELECT * STREAM result FROM src` |

`src[0]` in the field list identifies a record position, but `cell[0]` in `FROM` identifies a family instance. An ordinary stream is not indexed in `FROM`.

**Incorrect:**

```rql
SELECT vec[$] STREAM cell[3] FROM vec
SELECT * STREAM result FROM cell[3]
```

**Correct:**

```rql
SELECT vec[$] STREAM cell[3] FROM vec
SELECT * STREAM result FROM cell[2]
```

The diagnostic `outside the range 0..2` concerns a family index. Instances are numbered `0`, `1`, and `2`. Negative index-expression results and results that do not fit `int` are also rejected, as are duplicate families (`is declared more than once`) and generated-name collisions (`collides with a stream that already exists`). Change the index, size, or family name to match the intended computation.

A `DO SET` rule on a family produces `instances would write one variable in the same slot`. Each instance would attempt to modify the same variable. Attach the rule to a single named `SELECT` result that reads a chosen instance, or to a separate stream combining the family results.

**Incorrect:**

```rql
VAR COUNT = 0
SELECT vec[$] STREAM cell[3] FROM vec
RULE increase ON cell WHEN cell[0] > 0 DO SET ?COUNT = ?COUNT+1
```

**Correct:**

```rql
VAR COUNT = 0
SELECT vec[$] STREAM cell[3] FROM vec
SELECT * STREAM chosen FROM cell[0]
RULE increase ON chosen WHEN chosen[0] > 0 DO SET ?COUNT = ?COUNT+1
```

**Tests and requirements:** [Stream Families](../appendices/integration-tests.md#rql-tests-generators).

## RULE Statements

### Rule Target and Available Fields

A `RULE` attaches to an existing `SELECT` result. It cannot attach to a `DECLARE`. The condition and `DO SET` read the output record of the stream named in `ON`, not arbitrary sources used to compute it. Write field names and indices in the rule relative to that result.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `but no such stream is defined` | `RULE alarm ON missing WHEN 1 DO DUMP -1 TO 1` | `RULE alarm ON out WHEN 1 DO DUMP -1 TO 1` |
| `cannot be attached to declaration stream` | `RULE alarm ON src WHEN src[0] > 0 DO DUMP -1 TO 1` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -1 TO 1` |
| `reads only the record of the stream it is attached to` | `RULE alarm ON out WHEN src[0] > 0 DO DUMP -1 TO 1` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -1 TO 1` |
| `out of range` | `RULE alarm ON out WHEN out[2] > 0 DO DUMP -1 TO 1` | `RULE alarm ON out WHEN out[1] > 0 DO DUMP -1 TO 1` |

### Duplicate Name and DUMP Range

The diagnostic `is already defined on stream` means a rule name is duplicated on the same stream. Rename the second rule or remove the duplicate. The same name may be used on another stream provided it does not cause a dump filename collision.

**Incorrect:**

```rql
RULE alarm ON out WHEN out[0] > 10 DO DUMP -1 TO 1
RULE alarm ON out WHEN out[1] > 20 DO DUMP -1 TO 1
```

**Correct:**

```rql
RULE alarm_v ON out WHEN out[0] > 10 DO DUMP -1 TO 1
RULE alarm_w ON out WHEN out[1] > 20 DO DUMP -1 TO 1
```

The bounds of `DUMP L TO R` must satisfy `L < R`. The range is half-open, `[L,R)`. Both bounds may also be negative, for example `-5 TO -2`.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `left bound must be less than right bound` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP 2 TO 2` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -2 TO 2` |
| `exceeds the limit 256` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -1 TO 1 RETENTION 257` | `RULE alarm ON out WHEN out[0] > 0 DO DUMP -1 TO 1 RETENTION 8` |

`would write the same dump file as rule` concerns filename collisions. For example, the pairs stream `a` with rule `b_c` and stream `a_b` with rule `c` produce the same stem, `a_b_c`. The comparison ignores case. Rename the rule or stream so the stems differ. See [RULE Command](rule-command.md).

**Incorrect:**

```rql
SELECT * STREAM a FROM src
SELECT * STREAM a_b FROM src
RULE b_c ON a WHEN a[0] > 0 DO DUMP -1 TO 1
RULE c ON a_b WHEN a_b[0] > 0 DO DUMP -1 TO 1
```

**Correct:**

```rql
SELECT * STREAM a FROM src
SELECT * STREAM a_b FROM src
RULE b_c ON a WHEN a[0] > 0 DO DUMP -1 TO 1
RULE alarm ON a_b WHEN a_b[0] > 0 DO DUMP -1 TO 1
```

**Tests and requirements:** [RULE Targets, DUMP Ranges, and Dump Names](../appendices/integration-tests.md#rql-tests-rules).

## Sources, Storage, and Directives

### Options Incompatible with the Source Kind

`DEVICE` does not accept `DISPOSABLE` or `HOLD`; these options apply to `BINFILE` and `TEXTFILE`. `TIMEOUT` is allowed only with `DEVICE`, in the range from `0` to `86400` seconds. Zero is valid here, although it is forbidden as a stream interval.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `DEVICE does not take HOLD` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' HOLD` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero'` |
| `DEVICE does not take DISPOSABLE` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' DISPOSABLE` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero'` |
| `TIMEOUT applies to DEVICE` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt' TIMEOUT 1` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'` |
| `must not be negative` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' TIMEOUT -1` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' TIMEOUT 0` |
| `exceeds the limit 86400 s` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' TIMEOUT 86401` | `DECLARE x BYTE STREAM sensor, 1 DEVICE '/dev/zero' TIMEOUT 1` |
| `requires a non-empty file name` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE ''` | `DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'` |

If the data comes from a device or FIFO, choose `DEVICE` to match the actual source kind. Changing the keyword without changing the source kind may pass compilation but be rejected at startup. The grammar fixes the option order: `TIMEOUT`, `DISPOSABLE`, `ONESHOT`, `HOLD`. See [Read Options](declare-command-read-options.md).

### Invalid Profile or Empty Directive

`STORAGE` on a `SELECT` and the `SUBSTRAT` directive accept writable profiles: `DEFAULT`, `MEMORY`, `DIRECT`, `POSIX`, `POSIXSHD`, and `GENERIC`. `DEVICE`, `BINFILE`, and `TEXTFILE` specify `DECLARE` sources; they are not result storage profiles. The `STORAGE`, `SUBSTRAT`, and `ROTATION` directives require a nonempty value in single quotes.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `is not a storage profile` | `SELECT v STREAM result FROM src STORAGE DEVICE` | `SELECT v STREAM result FROM src STORAGE MEMORY` |
| `is not a storage profile` | `SUBSTRAT 'textsource'` | `SUBSTRAT 'memory'` |
| `requires a non-empty value` | `ROTATION ''` | `ROTATION 'rotation_counter.txt'` |
| `requires a non-empty file name` | `SELECT v STREAM result FROM src FILE ''` | `SELECT v STREAM result FROM src FILE 'wynik.bin'` |

### Conflicting VOLATILE, PERSISTENT, and DEFAULT VOLATILE

`PERSISTENT conflicts with STORAGE MEMORY` identifies contradictory persistence requirements. The grammar permits only one of `VOLATILE` or `PERSISTENT`. Query clauses follow this order: `FILE`, `RETENTION`, `VOLATILE` or `PERSISTENT`, `STORAGE`.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `PERSISTENT conflicts with STORAGE MEMORY` | `SELECT v STREAM result FROM src PERSISTENT STORAGE MEMORY` | `SELECT v STREAM result FROM src PERSISTENT STORAGE DEFAULT` |

`DEFAULT VOLATILE` may occur only once, before `DECLARE`, `SELECT`, and `RULE`. A duplicate produces `DEFAULT VOLATILE may occur only once`, and a misplaced directive produces `DEFAULT VOLATILE must precede DECLARE, SELECT and RULE`.

**Incorrect (complete plan):**

```rql
DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'
DEFAULT VOLATILE
SELECT * STREAM result FROM sensor
```

**Correct (complete plan):**

```rql
DEFAULT VOLATILE
DECLARE x INTEGER STREAM sensor, 1 TEXTFILE 'x.txt'
SELECT * STREAM result FROM sensor
```

### Retention Form Incompatible with Storage

`RETENTION N` defines an in-memory ring and requires `STORAGE MEMORY`, `VOLATILE`, or inherited `DEFAULT VOLATILE`. Segmented disk storage requires two arguments: `RETENTION capacity segment_count`. A second argument with in-memory storage is an error. A segment count of `0` means the number of segments is unlimited, not that the store is empty.

| Diagnostic fragment | Incorrect | Correct |
| --- | --- | --- |
| `sets only the size of a MEMORY ring` | `SELECT v STREAM result FROM src RETENTION 5` | `SELECT v STREAM result FROM src RETENTION 5 2` |
| `sets segments on disk` | `SELECT v STREAM result FROM src RETENTION 5 2 STORAGE MEMORY` | `SELECT v STREAM result FROM src RETENTION 5 STORAGE MEMORY` |

The first correction chooses disk retention. If RAM storage is required, keep one argument and add `VOLATILE` or `STORAGE MEMORY`.

### Retention Too Short for History Reads

`keeps only ... record(s) on disk ... but the plan reads ... record(s) back from it` means the plan could access a segment that has already been removed. Increase the capacity or segment count, or reduce the required history reach.

**Incorrect:**

```rql
SELECT v STREAM kept FROM src RETENTION 2 2
SELECT * STREAM result FROM kept>6
```

**Correct:**

```rql
SELECT v STREAM kept FROM src RETENTION 10 2
SELECT * STREAM result FROM kept>6
```

For `RETENTION C S` with `S > 0`, the guaranteed number of retained records after starting a new segment is `(S-1)*C+1`, rather than `S*C`. Simply multiplying the two arguments can therefore give an incorrect estimate. The same check covers default retention from the TOML configuration. See [STORAGE Types](select-command/storage-types.md).

### History Memory Budget

The diagnostic `Plan keeps ... bytes of stream history in memory; the budget [limits] history_memory_mib = ...` concerns the combined history of sources and in-memory stores. It also identifies the stream with the largest share, its record count, and record size. Reduce window sizes, shifts, or record widths; consider disk storage for intermediate results. Increase the TOML budget only after checking available memory. Switching to `VOLATILE` alone does not reduce the required history length.

Example with the default history memory budget: a 65536-byte record and a shift of 65536 records require history far exceeding that budget. Each argument individually fits the parser limits. The correction reduces the history reach:

**Incorrect (complete plan):**

```rql
DECLARE text STRING[65536] STREAM wide, 1 BINFILE 'szerokie.bin'
SELECT * STREAM result FROM wide>65536 VOLATILE
```

**Correct (complete plan):**

```rql
DECLARE text STRING[65536] STREAM wide, 1 BINFILE 'szerokie.bin'
SELECT * STREAM result FROM wide>10 VOLATILE
```

**Tests and requirements:** [Sources, Directives, and Retention](../appendices/integration-tests.md#rql-tests-storage).

## Ad Hoc and Plan Reload Refusals

The same parser and compiler checks apply to `xqry -a` and `xqry --reset` requests, but the response uses a different prefix. An ordinary refusal during validation leaves the running plan in place and does not terminate the server. Passing `xretractor -c` does not mean that the file's contents are allowed through every channel.

| Response fragment | Meaning and correction |
| --- | --- |
| `Fail parse: ...` | A syntax error, a parser semantic check, or an ad hoc channel restriction. The remaining text identifies the cause. |
| `Fail local chain compiler:...` | The compiler refused an ad hoc query or rule. Apply the catalogue's corrections for `Check result:`. |
| `Fail compile:...` | The compiler refused a new plan during `--reset` validation. |
| `Rejected: ...` | A source, storage, resource, or channel-policy check refused the request. This need not be a grammar error. |
| `AdHoc accepts exactly one SELECT, DECLARE or RULE statement` | Send one statement; use `--reset` to submit a complete plan. |
| `AdHoc accepts only SELECT, DECLARE or RULE; ... is not supported` | Standalone `LET`, `VAR`, and directives are not ad hoc commands. Put them in the plan file. |
| `stream '...' already exists in this instance` | An ad hoc request tries to redeclare an existing stream using `DECLARE`. Change the name or reload the complete plan. |
| `AdHoc RULE supports DO DUMP and DO SET only` | `DO SYSTEM` is not allowed in an ad hoc rule. |
| `keeps only ... record(s) in memory, but a dump range ... needs ...` | The new rule needs more history than the running stream's ring holds. Shorten the range or reload the plan with sufficient capacity. |
| `engine error: ...` | An engine invariant violation was reported through `error.response`; preserve the diagnostics for a defect report. |

For a validation refusal, the reset client adds `xqry: plan reload refused at reset-commit: ...`. Refusals at `reset-begin` and `reset-chunk` concern starting or transferring the plan, before the parser receives the complete text. By default, a plan submitted through reset cannot contain `DO SYSTEM`; the diagnostic names the rule and the `service.unrestricted` setting. See [Runtime Errors](../query-execution/runtime-errors.md#command-reset-and-ad-hoc-import-refusals) for that option's rules and transfer diagnostics.

An ad hoc request sees the running plan's declared `VAR` names, but not its `LET` constants, which disappear while parsing the file. An unknown `?N` diagnostic can therefore occur despite an earlier `LET N` in the startup file.

**Coverage:** `it_adhoc_parse_error-run`, `it_adhoc_rule-run`, `it_storage_refusal`, and the reset tests under `test/IntegrationTest/`.

## What Is Not a Syntax Error

Successful compilation does not confirm device availability, input file existence, compatibility of a retained descriptor, or permission to write to a directory. Diagnostics such as `source file does not exist`, `descriptor schema mismatch`, and `directory ... does not exist` concern sources or storage state, checked at startup and on other plan-loading paths. Resolve the cause by correcting paths, data, or permissions, or by reconciling storage with the plan. Do not blindly delete artifacts just because the parser accepted the query.

An expression such as `v/0`, or an invalid text-to-number conversion, may also pass compilation and produce `NULL` at runtime. This differs from a zero denominator in the **interval** `1/0`, which the parser rejects. A warning about an unused constant, deprecated notation, or unbounded storage growth likewise does not mean compilation was refused. Distinguish warnings, invalid plans, and calculation results.

## Catalogue Sources and Further Diagnostics

The catalogue is based on checks in the current implementation, rather than grammar diagrams alone:

| Source | Diagnostic scope |
| --- | --- |
| [RQL.g4](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/RQL.g4) | Statement structure, clause order, and the distinction between scalar, logical, and stream expressions. |
| [RQLParser.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/RQLParser.cpp) | Error positions, numbers and dimensions, source options, `LET`/`VAR`, rule attachment, directives, and retention forms. |
| [compiler.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/compiler.cpp) | References, dependencies, operators, generators, windows, functions, assignments, and history resources. |
| [expressionShape.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/expressionShape.cpp) | Rejections of unsupported combinations of an operator or function with an argument type. |
| [launcher.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/launcher.cpp) | The `Parse result:` and `Check result:` channels, the plan rejection code, and termination of `-c` mode. |
| [executorsmAdHoc.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/executorsmAdHoc.cpp), [executorsmPlanReload.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/src/retractor/lib/executorsmPlanReload.cpp) | Ad hoc and reset refusal prefixes and restrictions; validation before changing the running plan. |
| [test_compiler.cpp](https://github.com/michalwidera/retractordb/blob/39b59c698992c35bbafb0c8525b7c8cedd181ac6/test/UnitTest/test_compiler.cpp) | Rejection cases and valid control variants for the parser and compiler. |

The links pin the code revision used to prepare this chapter. Diagnostics about internally malformed tokens and violated invariants have no "incorrect/correct RQL" pair: they require a bug report. If the syntax is valid but the plan differs from expectations, use the [compilation debugging tools](../query-compilation/compilation-debugging.md); for the order of checks, see [Compilation Passes](../query-compilation/compilation-passes.md).
