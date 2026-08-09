# Query Compilation

An attentive reader will probably notice that, in the compiled query execution plans shown in the previous chapter, certain values don't match what was written in the query.

The compiler, while building a query plan, carries out the process autonomously. Sometimes it feels like you ask for one thing and get something else — at first glance this behavior seems entirely counterintuitive. And as a user, I fundamentally have no control over it. Interestingly, the outcome of the query does correspond to what I asked for in the query. Perhaps the correct title for this chapter should be: Why does the compiler do things its own way, and claim to know better?

In this chapter I want to explain how I solved the syntactic problems I encountered while building the query language.

## Compiler input and output

### The `.rql` file

Compiler input — text in the RetractorQL language containing `DECLARE` and `SELECT` directives. The ANTLR4 parser reads the file sequentially; a reference to a stream not yet defined earlier in the file results in a compilation error.

### The ANTLR4 parser → `qTree`

The parser builds an internal representation, `qTree`: a topologically sorted `std::vector<query>`. Each element describes one stream — its field schema, its stack-instruction sequence, its dependencies on other streams, and its time interval (delta).

### The 10 compilation stages

`qTree` passes through a chain of transformations: from breaking down FROM expressions into two-argument operations, through determining deltas and byte offsets, all the way to semantic verification and buffer-size computation. Each stage assumes the previous one succeeded.

### Execution plan → `dataModel`

At the output of compilation, every query in `qTree` has: a field schema with types and offsets, a delta, buffer sizes, and a ready instruction sequence. `dataModel` takes over this plan and executes it cyclically in real time.

The `-c` flag stops `xretractor` after this step and prints the plan to standard output — without starting processing.


## Overview of topics covered in this chapter

The chapter is structured following the order of the compiler's stages — from a description of the data structure and the chain of stages, through the individual transformations, to error handling.

[**Compilation Passes**](compilation-passes.md) describes the entire chain of stages in the `compiler::compile()` function. Compilation is not a single step — it's a sequence of ten successive transformations of the internal `qTree` representation, from reducing FROM expressions to two-argument form, through determining field intervals and offsets, all the way to semantic verification and buffer allocation. Each stage assumes the previous one succeeded, and returns an error message when its conditions aren't met.

[**Dependency Tree Construction**](dependency-tree-construction.md) describes the DAG structure produced during compilation — the foundation on which every stage rests. The roots are ephemeris declarations (external sources); inside the graph lie intermediate substrates; and the leaves are artifacts. The `-d` flag generates output in DOT format, which `graphviz` turns into a visual dependency graph. The order of queries in the `.rql` file matters — a reference to a stream not yet defined results in an error.

[**Substrates**](substrates.md) explains the `extractIntermediateStreams` stage — the first compilation step. When a FROM expression contains more than two arguments (e.g. `(core0#core1)+core2`, `core0+core1+core2`), the compiler breaks it down into two-argument operations and creates named substrates. A later stage, `deduplicateSubstrats`, detects when a substrate is structurally identical to a user query and replaces the references — avoiding duplicate computation.

[**Asterisk Expansion**](asterisk-expansion.md) explains the `expandSchemaWildcards` stage. The `*` symbol in a SELECT clause is replaced with the full field list derived from the source stream's schema — including fields arising from stream-sum operations. An example shows how field types determine which field ends up in which position of the resulting schema.

[**Interval Resolution**](interval-resolution.md) describes the `resolveStreamIntervals` stage. The compiler determines the delta of every output stream from the stream-algebra equations: for the `+` operator the delta is the minimum of the inputs, for `#` it's the harmonic mean, for `@(step, window)` it's a derivative of the window size. The algorithm runs iteratively — each round resolves at least one stream, until all deltas are known.

[**Loop Detection**](loop-detection.md) describes the mechanism built into the `resolveStreamIntervals` stage. If the number of unresolved streams stops decreasing, no stream can obtain a delta — a sign that the dependency graph contains a cycle. Compilation ends with the error `"Circular dependency in stream definitions"`. The chapter includes an example of a cyclic query and how to fix it.

[**Aliasing**](aliasing.md) describes the `resolveFieldReferences` and `localizeFieldOffsets` stages. After a sum `+`, an output field can be referenced either by its index in the combined schema (`str1[1]`) or by the source stream name with a local index (`core1[0]`). After an interleave `#`, the components share one schema, so named references to components are rejected; use the output stream name or de-interleave with `&`/`%`.

[**Underscore Symbol Processing**](underscore-symbol-processing.md) describes the `expandIndexWildcards` stage — syntactic sugar for parallel operations on pairs of fields. The `_` symbol in an index causes the formula to be repeated for every pair of fields from both arguments' schemas — `core0[_] * core1[_]` with two-field schemas generates two multiplying fields for the corresponding pairs. Use case: building signal-filter queries.

[**Type Promotion**](type-promotion.md) defines the type-promotion rules that apply throughout the compilation chain. The result of `BYTE * INTEGER` has type `INTEGER` — the compiler determines the output field's type statically, before any data is processed. The complete type hierarchy supported by RetractorDB is also described.

[**Compilation Debugging**](compilation-debugging.md) gathers diagnostic tools in one place: the `-c` flag for plan inspection, the `-c -d -f -s` pipeline for graph visualization via `graphviz`, a table of plan-instruction meanings (PUSH\_ID, PUSH\_STREAM, STREAM\_ADD, ...), and a catalog of common compilation errors with their causes and fixes.
