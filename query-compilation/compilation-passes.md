# Compilation Passes

Query compilation in RetractorDB proceeds through multiple stages. Each stage transforms the internal representation of the queries — the `qTree` tree — and passes the result to the next one. The order is strictly fixed: every stage assumes the previous one succeeded.

`qTree` is a topologically sorted `std::vector<query>` — the central data structure of the compiler and the executor. Every element of the vector corresponds to one query (`SELECT` or `DECLARE`) and stores its field schema, its stack-instruction sequence, its time interval, and references to its source streams. The topological sort guarantees that a source stream always precedes its output stream — stages can process `qTree` linearly, without backtracking.

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

Reduces every FROM expression to at most a two-argument form. Complex expressions like `(core0#core1)+core2`, and chained notations without parentheses (`core0+core1+core2`, `core0#core1#core2`), require intermediate streams. This stage automatically creates substrates — see [Substrates](substrates.md).

#### expandSchemaWildcards

Expands the `*` symbol in a SELECT clause. Replaces it with the field list derived from the source stream's schema — see [Asterisk Expansion](asterisk-expansion.md).

#### resolveStreamIntervals (← loops are detected here)

Determines the time interval (delta) of every stream based on the algebraic operators and the intervals of the input streams. An iterative algorithm — each round resolves as many streams as possible. It detects cyclic dependencies by stopping when the number of unresolved streams stops decreasing — see [Interval Resolution](interval-resolution.md) and [Loop Detection](loop-detection.md).

#### deduplicateSubstrats

An optimization: if two queries use the same intermediate operation (e.g. `core0#core1`), this stage points the second query at the substrate created by the first. It avoids duplicate computation — see the example in [Substrates](substrates.md).

#### resolveFieldReferences

Turns references to fields from source schemas into indices in the output schema. Handles aliasing — turning `core0[0]` into `str1[0]`, etc. — see [Aliasing](aliasing.md).

#### expandIndexWildcards

Expands the `_` symbol in field indices. Repeats the formula for every matching pair of fields from the arguments' schemas — see [Underscore Symbol Processing](underscore-symbol-processing.md).

#### localizeFieldOffsets

Converts field references (`b[x]`, `c[y]`) into indices in the flattened output schema (`merged[z]`). For ADD, the index follows from the sum of the field counts of the preceding streams; for HASH, every field gets index 0 (a single-argument schema). This stage accounts not only for direct sources, but also for transitive sources hidden behind automatic substrates.

#### computeRequiredCapacities

Computes the required buffer capacities for every stream, based on schema sizes and time-window requirements.

#### validateConstraints

Verifies the semantic correctness of the compiled plan: type compatibility, window sizes, availability of data sources.

#### applyCapacitiesToStreams

Applies the computed capacities to the stream objects. After this stage, the plan is ready for execution by `dataModel`.


Every stage returns `"OK"` or an error message — in which case compilation stops.
