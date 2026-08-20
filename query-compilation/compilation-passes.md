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

```
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

SELECT merged[0], merged[2], core0[0], core1[0] \
STREAM result \
FROM merged
```

After passing through all the stages, `xretractor -c query.rql` prints:

```
merged(1/10)
        :- PUSH_STREAM(core0)
        :- PUSH_STREAM(core1)
        :- STREAM_ADD
        core0_0: BYTE
                PUSH_ID(merged[0])
        core0_1: INTEGER
                PUSH_ID(merged[1])
        core1_2: INTEGER
                PUSH_ID(merged[2])
        core1_3: FLOAT
                PUSH_ID(merged[3])
result(1/10)
        :- PUSH_STREAM(merged)
        result_0: BYTE
                PUSH_ID(merged[0])
        result_1: INTEGER
                PUSH_ID(merged[2])
        result_2: BYTE
                PUSH_ID(merged[0])
        result_3: INTEGER
                PUSH_ID(merged[2])
core0(1/10)     sensor_a.txt
        a: BYTE
        b: INTEGER
core1(1/5)      sensor_b.txt
        c: INTEGER
        d: FLOAT
core2(3/10)     sensor_c.txt
        e: INTEGER
```

The subchapters on substrates and the `_` symbol use extended variants of the same set of declarations. For how to interpret every element of this plan, see [Compilation Debugging](compilation-debugging.md).

## The chain of stages

The chain of stages is defined by the `compiler::compile()` function:

#### extractIntermediateStreams

Reduces every FROM expression to at most a two-argument form. Complex expressions like `(core0#core1)+core2`, and chained notations without parentheses (`core0+core1+core2`, `core0#core1#core2`), require intermediate streams. Every query is reduced to a fixed point, so the stage also handles adjacent unary subexpressions such as `(core0>2)#(core1>1)`. This stage automatically creates substrates — see [Substrates](substrates.md).

#### expandSchemaWildcards

Expands the `*` symbol in a SELECT clause. Replaces it with the field list derived from the source stream's schema — see [Asterisk Expansion](asterisk-expansion.md).

#### resolveStreamIntervals (← loops are detected here)

Determines the time interval (delta) of every stream based on the algebraic operators and the intervals of the input streams. An iterative algorithm — each round resolves as many streams as possible. It detects cyclic dependencies by stopping when the number of unresolved streams stops decreasing — see [Interval Resolution](interval-resolution.md) and [Loop Detection](loop-detection.md).

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

#### resolveFieldReferences

Turns references to fields from source schemas into indices in the output schema. It handles aliases after sum — turning `core0[0]` into `str1[0]`, for example — and records the source to which a bare field name was resolved. Named references written by the user are tracked separately so a later pass does not confuse them with tokens synthesized by the compiler. See [Aliasing](aliasing.md).

#### expandIndexWildcards

Expands the `_` symbol in field indices. Repeats the formula for every matching pair of fields from the arguments' schemas — see [Underscore Symbol Processing](underscore-symbol-processing.md).

#### simplifyFieldExpressions

Simplifies `SELECT` field programs and `RULE` conditions after references have
been resolved but before equivalent computations are shared. The pass folds
constant expressions, combines constant tails in integer and rational
arithmetic, and removes type-compatible neutral elements (`E+0`, `E-0`,
`E*1`, `E/1`).

The pass preserves `NULL` semantics and type promotion. It therefore does not
simplify `E*0`, reassociate `FLOAT` or `DOUBLE` operations, or alter programs
whose type or operation cannot be established safely.

#### shareEquivalentSelectComputations

Detects explicit `SELECT` queries with equivalent field programs and `FROM` trees containing `STREAM_ADD`. It orders only the two children of an individual `STREAM_ADD` node without changing the grouping of the complete tree. For each equivalence class it creates one `STREAM_SELECT_*` substrate and retains the public queries as lightweight projections with their own names, descriptors, rules, and storage. The pass runs before field-offset localization — see [Substrates](substrates.md).

#### localizeFieldOffsets

Converts field references (`b[x]`, `c[y]`) into positions in the flattened output schema (`merged[z]`). For sum `+`, the offset follows from the number of fields in the preceding components. For interleave `#`, both arguments share the same positions in one schema; component identity is no longer available through its name.

At this stage the compiler rejects user-written `A[0]`, `A.field`, `A[_]`, `A.*`, and bare field names if they refer to a component reached through `#`. The check also covers `RULE` conditions and sources hidden behind automatic substrates. References through the output stream name, an unqualified `*`, and explicit component recovery with `&` or `%` remain legal.

#### computeLogicalOrigin

Computes `query::logicalOrigin`, the index of the first record that **exists at
all**. The difference from the tail is qualitative: the tail says "not yet",
the origin says "this record has no definition". The origin originates from the
`@(k,L)` window stamped by the interval end — its early records would reach
before the start of the source — and from the shift `>N`, whose record `n`
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
window, and reductions add no own tail. The plan listing shows `tail=` and the
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

#### validateConstraints

Verifies the semantic correctness of the compiled plan: type compatibility, window sizes, availability of data sources.

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


Every stage returns `"OK"` or an error message — in which case compilation stops.
