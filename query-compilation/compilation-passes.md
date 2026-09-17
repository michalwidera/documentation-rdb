# Compilation Passes

Query compilation in RetractorDB proceeds through multiple stages. Each stage transforms the internal representation of the queries — the `qTree` tree — and passes the result to the next one. The order is strictly fixed: every stage assumes the previous one succeeded.

`qTree` is a `std::vector<query>` — the central data structure of the
compiler and executor. Every element corresponds to one query (`SELECT` or
`DECLARE`) and stores its field schema, stack-instruction sequence, time
interval, startup tail, and references to source streams. Not every stage
preserves vector order: interval resolution sorts it by `rInterval`.
Compilation therefore ends with an unconditional topological sort, which
guarantees that a producer precedes its consumer during execution.

## Running example

Throughout the chapter we follow a single query — `query.rql` — through the successive stages:

```rql
DECLARE a BYTE, b INTEGER \
STREAM core0, 0.1 \
FILE 'sensor_a.txt'

DECLARE c INTEGER, d FLOAT \
STREAM core1, 0.2 \
FILE 'sensor_b.txt'

DECLARE e INTEGER \
STREAM core2, 0.3 \
FILE 'sensor_c.txt'

SELECT * \
STREAM merged \
FROM core0 + core1

SELECT merged[0], merged[2] \
STREAM result \
FROM merged
```

After passing through all the stages, `xretractor -c query.rql` prints:

```rasm
{{#include ../regen/out/compile-flow.txt}}
```

The plan is printed in the final topological order: the declarations `core0` and `core1` precede their consumer `merged`, which precedes the query `result`. The unused declaration `core2` goes last. `tail=1` is the startup tail determined by `computeStartupLatency`. `PUSH_ID` references point to positions in the query's input record, written under the query's own name: `result[2]` is the third field of the `merged` record, that is `core1.c`.

The field list of `result` refers only to the stream in its own `FROM` clause. Writing `core1[0]` there ends in the compilation error `Stream 'result' refers to 'core1', which is not in its FROM clause`: `core1` is a source of `merged`, not of `result` — see [Aliasing](aliasing.md).

The subchapters on substrates and the `_` symbol use extended variants of the same set of declarations. For how to interpret every element of this plan, see [Compilation Debugging](compilation-debugging.md).

## The chain of stages

The chain of twenty-three stages is defined by the `compiler::compile()` function:

<div class="timeline compact">

- `checkFunctionCalls` — scalar-function names and arity
- `checkStreamReducerFieldRefs` — stream reducer outside the `FROM` clause
- `expandStreamGenerators` — expansion of `name[N]` stream families
- `snapshotNamedSourceRefs` — snapshot of user-written references
- `extractIntermediateStreams` — two-argument `FROM` expressions, substrates
- `expandSchemaWildcards` — expansion of `*` and `[_]`
- `resolveStreamIntervals` — stream intervals, loop detection
- `factorMatchedHashTimeMoves` — factoring a common shift out of an interleave
- `deduplicateSubstrats` — elimination of repeated substrates
- `validateSubstratNameUniqueness` — unambiguous substrate names
- `resolveFieldReferences` — field references as flat indexes
- `resolveWindowAggregates` — record-history aggregate groups
- `inferFieldShapes` — type, length, and cardinality of every field
- `checkRuleConditionShapes` — computability of `RULE` conditions
- `simplifyFieldExpressions` — simplification of field and rule programs
- `shareEquivalentSelectComputations` — sharing equivalent `SELECT` computations
- `localizeFieldOffsets` — field offsets in the input buffer
- `computeLogicalOrigin` — logical origin of a stream
- `computeStartupLatency` — startup tail
- `computeRequiredCapacities` — required buffer history
- `validateConstraints` — semantic validation of the plan
- `applyCapacitiesToStreams` — capacity application
- `topologicalSort` — final producer–consumer order

</div>

The stages `factorMatchedHashTimeMoves`, `deduplicateSubstrats`, `simplifyFieldExpressions`,
and `shareEquivalentSelectComputations` are optimizations that the `RDB_OPT_*` switches can
disable. Disabling them does not change result values; at most it can lengthen the startup
tail (see `factorMatchedHashTimeMoves`). All other stages always run.

#### checkFunctionCalls

Validates scalar-function names and arity against the single `rqlFunctions.hpp` table.
Matching is case-insensitive and the canonical spelling is stored in the token. An unknown
function or invalid width stops compilation through `Check result:` before generator
expansion, so one template error is not multiplied N times.

#### checkStreamReducerFieldRefs

Rejects a stream reducer (`MIN`, `MAX`, `AVG`, `SUMC` without a window width) used in a
`SELECT` field program or in a `RULE` condition. The grammar admits it in a scalar
expression, but no execution mechanism evaluates it there: the query
`SELECT avg STREAM o FROM AVG(src)` used to pass compilation and then never emitted a single
record. A stream reducer belongs in the `FROM` clause; the working `SELECT * FROM AVG(src)`
is not affected by this check. The stage sits next to `checkFunctionCalls` for the same
reason — before generator expansion.

#### expandStreamGenerators

Expands every `SELECT ... STREAM name[N] ...` template into `N` ordinary queries named `name$0`...`name$(N-1)` and substitutes the instance ordinal for `$` in fields, values, and `FROM` references. It is the first pass that rewrites the plan (only the `checkFunctionCalls` and `checkStreamReducerFieldRefs` checks precede it): everything after it receives a plan indistinguishable from hand-written queries. See [SELECT Command](../query-language-construction/select-command/README.md#stream-generators) for syntax and constraints.

#### snapshotNamedSourceRefs

Snapshots source references written by the user before substrates are created. Later field
localization uses the snapshot to distinguish legal synthetic tokens from references to a
component of `#`, whose identity is no longer preserved by the result.

#### extractIntermediateStreams

Reduces every FROM expression to at most a two-argument form. Complex expressions like `(core0#core1)+core2`, and chained notations without parentheses (`core0+core1+core2`, `core0#core1#core2`), require intermediate streams. Every query is reduced to a fixed point, so the stage also handles adjacent unary subexpressions such as `(core0>2)#(core1>1)`. This stage automatically creates substrates — see [Substrates](substrates.md).

#### expandSchemaWildcards

Expands both `*` in the SELECT clause and the `[_]` index. It replaces an asterisk with fields derived from the source schema. A formula containing `x[_]` is replicated according to the number of slots that `x` contributes to the record produced by the complete `FROM` clause, rather than the width of stream `x` itself. A one-field `x` under the window `x@(1,5)` therefore yields five elements. If the named contribution does not form a contiguous block of fields in `FROM`, compilation fails instead of assuming an arbitrary width.

At this stage, derived schemas expand a numeric `T[N]` entry into N scalar fields. A
declaration descriptor still retains one array entry, while byte layout and flat-slot order
remain unchanged. `STRING[N]` remains one text field. Stream operators, reducers, AGSE, and
payloads therefore use the same indexing unit. See [Asterisk Expansion](asterisk-expansion.md)
and [Underscore Symbol Processing](underscore-symbol-processing.md).

#### resolveStreamIntervals (← loops are detected here)

Determines the time interval (delta) of every stream based on the algebraic operators and the intervals of the input streams. An iterative algorithm resolves as many streams as possible in each round. A record-history aggregate in the `SELECT` list does not change the interval and requires one plain stream reference in `FROM`; a compound clause is rejected here. The pass detects cyclic dependencies by stopping when the number of unresolved streams stops decreasing — see [Interval Resolution](interval-resolution.md) and [Loop Detection](loop-detection.md).

#### factorMatchedHashTimeMoves

Recognizes matched shifts of interleave arguments. When `i·ΔA=k·ΔB`, it rewrites `(A>i)#(B>k)` as `(A#B)>(i+k)`, reducing two shift substrates to one interleave substrate. Unmatched cases and substrates shared with other consumers remain unchanged — see [Substrates](substrates.md).

A shift moves silence into the logical origin rather than inserting prefix
records. Equality of the physical shifts makes both sides of the rule carry the
same emitted sequence and the same logical origin. **The tails are not equal**:
the factored side reads content directly from the interleave, so it is ready no
later — and usually earlier — than the side that reads components after their
own shift. The rule is therefore a latency optimization, not a neutral rewrite;
for the scope of theorem R1 and a counterexample see [Formal foundations and
proofs](../mathematical-foundations/formal-foundations-and-proofs.md).

#### deduplicateSubstrats

An optimization: if two queries use the same intermediate operation (e.g. `core0#core1`), this stage points the second query at the substrate created by the first. It avoids duplicate computation — see the example in [Substrates](substrates.md).

#### validateSubstratNameUniqueness

Checks that two substrates with the same name denote the same program. Names longer than 200 bytes are shortened deterministically by `composeStreamName()`, so this check turns an extremely unlikely 64-bit digest collision into a loud error instead of an ambiguous plan. It runs independently of optimizer switches and after deduplication, because identical duplicate names are a normal transient state before that point.

#### resolveFieldReferences

Turns references to fields from source schemas into flat indices in the output schema. It handles aliases after sum — turning `core0[0]` into `str1[0]`, for example — and records the source to which a bare field name was resolved. Named references written by the user are tracked separately so a later pass does not confuse them with tokens synthesized by the compiler. A bare numeric-array name is rejected: `a` does not mean `a[0]`; an element must be selected. See [Aliasing](aliasing.md).

#### resolveWindowAggregates

Extracts the argument program of each `MIN`/`MAX`/`AVG`/`SUMC(expression : W)` in the
`SELECT` list into `query::windowGroups`. It validates positive width, numeric type, one
history source, at least one field read, and the bans on nesting and `RULE` use. Identical
source–expression–width triples share a group and one history scan. The aggregate token
becomes a zero-argument operand that points to the computed group result.

#### inferFieldShapes

The only stage that establishes the public shape of a `SELECT` field: its type, length, and
cardinality. The shape follows from the whole field program — the pass replays the runtime
arithmetic on a stack of types, including `BYTE` promotion, explicit conversions in the middle
of an expression, the result of a record-history aggregate, and the width of `STRING`. The
stage replaced the earlier local rules (`propagateCopiedFieldShapes`, `inferStringFieldTypes`),
which settled the shape only in selected cases — see [Type Promotion](type-promotion.md).

The pass runs to a fixed point because the tree is still sorted by interval and a consumer may
precede its producer. It covers only nodes that copy their operand's schema; reducers and the
`@` window keep the schema built by their operator, and `DECLARE` declarations are left
untouched. The stage precedes expression simplification: after constant folding, a field's
width would depend on an optimization switch.

#### checkRuleConditionShapes

Applies to `RULE` conditions the same computability check that `inferFieldShapes` applies to
fields. A rule condition is executed by the same expression evaluator, so without this stage an
invalid condition would bypass the check and silently produce a wrong value. The pass writes
nothing into the plan — it only rejects conditions that cannot be computed.

#### simplifyFieldExpressions

Simplifies `SELECT` field programs, record-history aggregate arguments, and `RULE` conditions after references have
been resolved but before equivalent computations are shared. The pass folds
constant expressions, combines constant tails in integer and rational
arithmetic, and removes type-compatible neutral elements (`E+0`, `E-0`,
`E*1`, `E/1`). It also writes a repeated exact factor as a power, for example
`E*E*E` as `E^3`.

The pass preserves `NULL` semantics and type promotion. It therefore does not
simplify `E*0`, reassociate `FLOAT` or `DOUBLE` operations, or alter programs
whose type or operation cannot be established safely. Repeated-factor folding
is limited to types with exact multiplication (`BYTE`, `INTEGER`, `UINT`, and
`RATIONAL`); it does not replace one `FLOAT` or `DOUBLE` multiplication with a
call to `pow`.

#### shareEquivalentSelectComputations

Detects explicit `SELECT` queries with equivalent field programs and `FROM` trees containing `STREAM_ADD`. It orders only the two children of an individual `STREAM_ADD` node without changing the grouping of the complete tree. For each equivalence class it creates one `STREAM_SELECT_*` substrate and retains the public queries as lightweight projections with their own names, descriptors, rules, and storage. The pass runs before field-offset localization — see [Substrates](substrates.md).

#### localizeFieldOffsets

Converts field references (`b[x]`, `c[y]`) into positions in the query's flattened input record, written under the query's own name (`result[z]`). For sum `+`, the offset follows from the number of fields in the preceding components. For interleave `#`, both arguments share the same positions in one schema; component identity is no longer available through its name.

A position can be determined only for streams in the `FROM` clause and for sources reached through compiler-generated substrates. A reference to a source of an intermediate stream that is a user query — e.g. `core1[0]` with `FROM merged` — stops compilation with `Stream '…' refers to '…', which is not in its FROM clause`. Such a stream has its own interval and buffer, so the position of its sources in the consumer's input record cannot be determined.

At this stage the compiler rejects user-written `A[0]`, `A.field`, `A[_]`, `A.*`, and bare field names if they refer to a component reached through `#`. The check also covers `RULE` conditions and sources hidden behind automatic substrates. References through the output stream name, an unqualified `*`, and explicit component recovery with `&` or `%` remain legal.

#### computeLogicalOrigin

Computes `query::logicalOrigin`, the index of the first record that **exists at
all**. The difference from the tail is qualitative: the tail says "not yet",
the origin says "this record has no definition". The origin originates from the
`@(k,L)` window stamped by the interval end — its early records would reach
before the start of the source — from a history aggregate, which adds `W-1`, and from the shift `>N`, whose record `n`
carries record `n-N`. Every other operator merely propagates the origin, through
the same index mapping it reads with.

For `@` and `>N` the form is closed; for `+`, `#`, `-`, `Theta` and `~Theta` the
pass **searches** for the smallest index reaching the component threshold, by
bisection over a non-decreasing mapping. The plan listing shows `origin=`.

#### computeStartupLatency

Computes `query::startupLatency`, the number of initial slots of the stream's
own interval in which an existing result is not yet ready. Sources have tail 0;
`>N` gives `max(0, W_src − N)`, because it reads a record older than the current
one; interleave includes both input tails and its own look-ahead on the second
argument; sum takes the maximum of both inputs' availability bounds. Difference
and both de-interleaves use exact phase bounds — left de-interleave does not
unconditionally add one slot. AGSE uses the bound from the newest field in its
window, and reductions and record-history aggregates add no own tail. The plan listing shows `tail=` and the
runtime emits no record during the tail. The number of silent slots is
`origin + tail`.

This pass runs after `computeLogicalOrigin` and before capacity computation: the
tail depends on which slots are records, and retained history depends on the
consumer's first emission time.

#### computeRequiredCapacities

Computes required buffer capacities from the distance between the producer's
head and the index read by a consumer. For a `>N` shift, the backward distance
is `W_out-W_src+N`, so the base capacity is `W_out-W_src+N+1`. If the source is
a declaration, two look-ahead records are added: the record armed when storage
is opened and the zero prefetch. The result is clamped to at least one record.
History capacity is an execution requirement, not a result prefix.

A record-history aggregate requires at least W consecutive records of its named source.
Capacity also accounts for logical origin, tail, and interval differences like every other
history read; it is not selected as a local `W` alone.

#### validateConstraints

Verifies semantic correctness of the compiled plan: type and flat-width compatibility,
window sizes, source availability, and operator constraints. Interleave `#` requires equal
flat schemas whether an input was written as `T[N]` or as N scalar fields.

#### applyCapacitiesToStreams

Applies the computed capacities to the stream objects.

For an interleave, the compiler reduces
\\(\Delta_a/\Delta_b=p/q\\) to coprime positive \\(p,q\\) and scans **one full
phase period** \\(p+q\\). For each slot \\(i\\) of that period it determines
which component the interleave selects and at which index \\(j(i)\\), then takes
the maximum of the required latency:

\\[
W_{\\#}
=\max_{0\le i<p+q}\left(
\left\lceil\frac{\bigl(j(i)+1+W_{s(i)}\bigr)\Delta_{s(i)}}{\Delta_c}\right\rceil
-1-i
\right)
\\]

The result is exact — it neither undershoots nor overshoots the causal bound.
The arithmetic runs in 64 bits, because the product
\\((j+1+W)\cdot\text{numerator}\cdot\text{denominator}\\) exceeds `int` range
already for moderate intervals. Above the `kHashPhaseScanLimit` threshold
(`SOperations.hpp`) the scan stops being affordable and the former closed form
\\(\lceil(p+q-1)/p\rceil\\) takes over; it overshoots the tail by one slot — a
safe choice, since undershooting would mean emitting a record before its
dependency is determined.

Regressions cover ratios including \\(3/5\\), \\(3/2\\), \\(7/11\\), and
\\(160/147\\), including periodic all-`NULL` records in the blocked,
non-rewritten left-hand side of the R1 identity; the operator formula itself is
guarded by `ut_h10aGate`.

#### topologicalSort

Unconditionally restores final producer–consumer order. This is part of
execution correctness, not presentation: a `#` result has a smaller
interval than its inputs, so earlier interval sorting can place the
consumer before its producers.

Plan-rewriting passes are additionally wrapped in
`verifyUserFieldNamesPreserved()`. Optimization may change or remove
internal substrates, but it cannot change field names of a public stream,
because those names enter the observable `.desc` descriptor.


Check and rewrite stages return `"OK"` or an error message — in which case compilation stops. `snapshotNamedSourceRefs`, `computeRequiredCapacities` (which returns the capacity map), and `topologicalSort` return no result of this kind. Some plan inconsistencies, such as a reference to a nonexistent stream, stop compilation with an exception instead of a message.
