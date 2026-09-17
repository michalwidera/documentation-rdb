# Query Compilation

An attentive reader will probably notice that, in the compiled query execution plans shown in the previous chapter, certain values don't match what was written in the query.

The compiler, while building a query plan, carries out the process autonomously. Sometimes it feels like you ask for one thing and get something else - at first glance this behavior seems entirely counterintuitive. And as a user, I fundamentally have no control over it. Interestingly, the outcome of the query does correspond to what I asked for in the query. Perhaps the correct title for this chapter should be: Why does the compiler do things its own way, and claim to know better?

In this chapter I want to explain how I solved the syntactic problems I encountered while building the query language.

## Compiler input and output

### The `.rql` file

Compiler input - text in the RQL language containing `DECLARE`, `SELECT`, and `RULE` statements as well as configuration directives (e.g. `:STORAGE`). The ANTLR4 parser reads the file statement by statement.

The order of `DECLARE` and `SELECT` in the file does not matter: a query may refer to a stream defined further down, because dependencies between streams are resolved only by the compiler. `RULE` is the exception - the parser attaches a rule to a stream that has already been read, so a rule must come after the definition of its stream; otherwise the parser reports `Rule '…' refers to stream '…', but no such stream is defined`. A reference to a stream that does not exist anywhere in the file stops compilation with `Referenced Stream in QUERY _not found_ in CORE TREE`.

### The ANTLR4 parser → `qTree`

The parser builds the internal representation `qTree` - a `std::vector<query>` - by appending one element for every `DECLARE` and `SELECT` statement and configuration directive, in file order and without sorting. A `SELECT` element carries the field schema with its stack programs and the `FROM` program that names the source streams. At this point the time interval (delta) is known only for `DECLARE` declarations; for `SELECT` queries the compiler determines it. A `STREAM name[N]` generator template is still a single element, and a `RULE` does not create an element of its own - it goes onto the rule list of its stream.

The order of the vector changes during compilation: interval resolution sorts it by delta, and the topological order (producer before consumer) is restored only by the last stage.

### The 23 compilation stages

`qTree` passes through an ordered chain of transformations: from breaking down FROM expressions into two-argument operations, through determining deltas, simplifying expressions, and locating fields, all the way to semantic verification, buffer-size computation, and the final topological sort. Each stage assumes the previous one succeeded.

### Execution plan → `dataModel`

At the output of compilation, every query in `qTree` has: a field schema with types and offsets, a delta, buffer sizes, and a ready instruction sequence. `dataModel` takes over this plan and executes it cyclically in real time.

The `-c` flag stops `xretractor` after this step and prints the plan to standard output - without starting processing.


## Overview of topics covered in this chapter

The chapter is structured following the order of the compiler's stages - from a description of the data structure and the chain of stages, through the individual transformations, to error handling.

<div class="timeline">

- **[Compilation Passes](compilation-passes.md)**

  Describes the entire chain of stages in the `compiler::compile()` function. Compilation is not a single step - it is an ordered sequence of twenty-three stages over the internal `qTree` representation, from expanding generators and reducing FROM expressions to two-argument form, through determining intervals, validating substrate names, simplifying expressions, and locating fields, all the way to semantic verification, buffer allocation, and the final topological sort. Each stage assumes the previous one succeeded, and an error at any stage stops compilation.

- **[Dependency Tree Construction](dependency-tree-construction.md)**

  Describes the DAG structure produced during compilation - the foundation on which every stage rests. The roots are ephemeris declarations (external sources); inside the graph lie intermediate substrates; and the leaves are artifacts. The `-d` flag generates output in DOT format, which `graphviz` turns into a visual dependency graph. The order of `DECLARE` and `SELECT` in the `.rql` file does not matter - the compiler builds the dependency graph; only a `RULE` must come after the definition of the stream it refers to.

- **[Substrates](substrates.md)**

  Explains the `extractIntermediateStreams` stage - the first step after generator expansion. When a FROM expression contains more than two arguments (e.g. `(core0#core1)+core2`, `core0+core1+core2`), the compiler breaks it down into two-argument operations and creates named substrates. A later stage, `deduplicateSubstrats`, detects when a substrate is structurally identical to a user query and replaces the references - avoiding duplicate computation.

- **[Asterisk Expansion](asterisk-expansion.md)**

  Explains the `expandSchemaWildcards` stage. The `*` symbol in a SELECT clause is replaced with the full field list derived from the source stream's schema - including fields arising from stream-sum operations. An example shows how field types determine which field ends up in which position of the resulting schema.

- **[Interval Resolution](interval-resolution.md)**

  Describes the `resolveStreamIntervals` stage. The compiler determines the delta of every output stream from the stream-algebra equations: for the `+` operator the delta is the minimum of the inputs, for `#` it's the harmonic mean, for `@(step, window)` it's a derivative of the window size. The algorithm runs iteratively - each round resolves at least one stream, until all deltas are known.

- **[Loop Detection](loop-detection.md)**

  Describes the mechanism built into the `resolveStreamIntervals` stage. If the number of unresolved streams stops decreasing, no stream can obtain a delta - a sign that the dependency graph contains a cycle. Compilation ends with the error `"Circular dependency in stream definitions"`. The chapter includes an example of a cyclic query and how to fix it.

- **[Aliasing](aliasing.md)**

  Describes the `resolveFieldReferences` and `localizeFieldOffsets` stages. After a sum `+`, an output field can be referenced either by its index in the combined schema (`str1[1]`) or by the source stream name with a local index (`core1[0]`). After an interleave `#`, the components share one schema, so named references to components are rejected; use the output stream name or de-interleave with `&`/`%`.

- **[Underscore Symbol Processing](underscore-symbol-processing.md)**

  Describes the `expandIndexWildcards` stage - syntactic sugar for parallel operations on pairs of fields. The `_` symbol in an index causes the formula to be repeated for all compatible slots that the referenced stream contributes to the record produced by the complete `FROM` clause. Thus `src[_] * coef[_]` with `FROM src@(1,5)+coef` generates five products even though `src` itself has only one field. Use case: building signal-filter queries.

- **[Type Promotion](type-promotion.md)**

  Defines the type-promotion rules that apply throughout the compilation chain. The result of `BYTE * INTEGER` has type `INTEGER` - the compiler determines the output field's type statically, before any data is processed. The complete type hierarchy supported by RetractorDB is also described.

- **[Compilation Debugging](compilation-debugging.md)**

  Gathers diagnostic tools in one place: the `-c` flag for plan inspection, the `-c -d -f -s` pipeline for graph visualization via `graphviz`, a table of plan-instruction meanings (PUSH\_ID, PUSH\_STREAM, STREAM\_ADD, ...), and a catalog of common compilation errors with their causes and fixes.

</div>
