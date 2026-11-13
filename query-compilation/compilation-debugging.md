# Compilation Debugging

The compiler transforms an `.rql` file into an execution plan through several stages. The effect of each stage is visible through `xretractor`'s diagnostic flags. The tools described here let you answer questions like: why does the schema look different from what I wrote? where does this delta come from? why did a substrate appear?

## The basic tool: the `-c` flag

The `-c` (`--onlycompile`) flag stops `xretractor` after compilation and prints the compiled plan to standard output - without starting processing:

```bash
xretractor -c query.rql
```

An exit code of `0` means success. A parser or compiler refusal of an invalid plan returns `EPROTO`, which is `71` on Linux. Other failures, such as a missing `.rql` file or an internal error, can use different codes; scripts should check every nonzero result. Error messages go to stderr:

```bash
xretractor -c query.rql >plan.txt 2>errors.txt
status=$?
printf 'exit=%s\n' "$status"
cat errors.txt
```

Compilation can be invoked even while another `xretractor` process is already running - the `-c` flag does not attempt to acquire the execution lock.

Save the exit code immediately: after `cat`, `$?` would describe reading the file rather than compilation. On refusal, `plan.txt` is not a completed plan. Early program diagnostics such as `fatal error: no input file` can go to stdout, so keep both files.

## Identify the Refusal Stage

| Diagnostic or situation | Stage and next step |
| --- | --- |
| `fatal error: no input file`, `file ... does not exist`, `Error: Unable to open file!` | The RQL file was not loaded. Check the program argument, working directory, and access to the plan file itself. |
| `fatal error: no queries to process` | `-c` found no plan to compile, for example in a file containing only comments. A normal start without statements can remain idle. |
| `Syntax error @Rql`, `Parse result:...` | Parser refusal. Check the first error, position, and named file. |
| `Check result:...` | Compiler refusal, or a plan error detected during initialization on a normal start. Read the remaining text; the prefix alone does not identify the correction. |
| `Fail parse:`, `Fail local chain compiler:`, `Fail compile:`, `Rejected:` | A response to an ad hoc or reset request. Check the cause and the channel's restrictions. |
| `FATAL: internal compiler error: ...`, `engine error: ...` | Engine defect diagnostics. Save a minimal plan, the full message, and build information. |

The [Syntax and Compilation Errors](../query-language-construction/syntax-and-compilation-errors.md) catalogue contains incorrect and corrected queries. Repeat the check after removing the first cause; compilation stops at its first refusal, so the next one may come from a different pass.

## How to read the compilation plan

For the canonical `query.rql` from this chapter, the plan looks as follows:

```rasm
{{#include ../regen/out/debug.txt}}
```

A computed stream's block has the following format; square brackets mark optional annotations and are not part of the output:

```rasm
streamName(delta) [tail=W] [origin=O]
        :- streamOperation(arg)
        outputFieldName: TYPE
                instruction
                ...
```

| Element | Meaning |
|---------|-----------|
| `streamName(delta)` | The stream's name and its interval as a fraction: `1/10` = 0.1 s = 10 Hz |
| `tail=W` | Startup tail: the delay in record availability, measured in slots of this stream |
| `origin=O` | Logical origin: the index of the first existing record; records at lower indices have no definition |
| `:- PUSH_STREAM(x)` | Pushes stream `x` onto the stream stack; appears once per FROM argument |
| `:- STREAM_ADD` | The stream-sum operator (`+` in FROM) |
| `:- STREAM_HASH` | The stream-interleave operator (`#` in FROM) |
| `:- STREAM_TIMEMOVE(n)` | Time shift (`>n` in FROM) |
| `field: TYPE` | An output-schema field, after type promotion |
| `PUSH_ID(s[n])` | Pushes the value of field `n` from stream `s` onto the stack - the effect of aliasing is visible here |
| `PUSH_VAL(x)` | Pushes the constant `x` onto the stack |
| `ADD`, `MULTIPLY`, ... | An arithmetic operation: pops two arguments off the stack, pushes the result |

The `tail` and `origin` annotations are printed only for positive values; an absent annotation means zero. When both occur, `tail` precedes `origin`. See [Tails, Logical Origins and Operator Observability](../mathematical-foundations/operator-tails-and-observability.md) for details of both quantities.

The plan is topologically ordered: every producer appears before the streams that consume it. Ephemeris blocks (`DECLARE`) contain the field list and the path to the data file.

**Aliasing in the plan**: if two output fields point to the same `PUSH_ID`, they are aliases. In the example, `result_0` and `result_2` are both `PUSH_ID(merged[0])` - confirmation that `merged[0]` and `core0[0]` are the same position. See [Aliasing](aliasing.md).

**Substrates in the plan**: an automatically generated substrate appears as a block with a name like `STREAM_HASH_core0_core1` - with no corresponding `SELECT` in the source file. See [Substrates](substrates.md).

## Visualizing the dependency graph

Instead of text, you can generate a graph in DOT format and process it with `graphviz`:

```bash
xretractor -c -d -f -t -s query.rql > out.dot && dot -Tsvg out.dot -o out.svg
```

Available flags that modify the DOT output:

| Flag | Full name       | Meaning |
|-------|-----------------|-----------|
| `-d`  | `--dot`         | generate DOT output instead of a text plan |
| `-f`  | `--fields`      | show stream fields in the graph nodes |
| `-t`  | `--tags`        | show individual field programs (requires `-f`) |
| `-s`  | `--streamprogs` | show stack-instruction sequences in the nodes |
| `-u`  | `--rules`       | show RULE rules |
| `-p`  | `--transparent` | transparent background - for embedding in documents |

The graph shows dependencies between streams as edges directed from sources to results. Substrates have a different color than streams explicitly defined by the user. See [Dependency Tree Construction](dependency-tree-construction.md).

DOT output is produced only after **successful compilation**. `-d` does not show a partial graph of a refused plan. Invoke `dot` through `&&`, as above, so a compilation refusal does not lead to processing an empty or incomplete file.

> **_NOTE:_** The functionality described here is covered by the test: `issue31_doc`, described in the appendix [Integration Tests](../appendices/integration-tests.md).

## Verifying intervals

If an output stream's delta is unexpected:

1. Check the source streams' deltas - visible in the DECLARE blocks before their consumers.
2. Check the operator in the FROM clause - every operator has a different delta equation.

Example: `core0(1/10) # core1(1/5)` gives a delta of `1/15`: input rates add up (`10 Hz + 5 Hz = 15 Hz`), so the interval is `a*b/(a+b)`. The sum `core0 + core1` gives a delta of `1/10` here, but it also combines both inputs' fields in one record; interleave `#` selects a record from one component. Choose the operator for the required schema and values as well. Full equations - see [Interval Resolution](interval-resolution.md).

## Common compilation errors

### Invalid literal or interval

A number outside the target type's range stops parsing with `numeric literal ... is out of range` in `Parse result:`. A zero denominator produces `fraction ... has a zero denominator`, and a zero interval produces `interval ... must be greater than zero`. This applies to startup files and ad hoc requests; in the latter case the refusal leaves the server running. Correct the number or choose a positive interval. A `Circular dependency` message indicates a dependency cycle, not a zero interval.

### A cycle in the dependency graph

The refusal status is `Check result:Circular dependency in stream definitions`. The log may also contain `Circular dependency: stream interval resolution stalled with N unresolved streams`.

Trace the references in the RQL file's `FROM` clauses until you find a return to an earlier stream. Remove the cyclic dependency; changing line order does not remove it. A direct read of the stream's own output may be refused earlier with `a stream cannot be its own producer`. For a refused plan, `-d` also returns a refusal, so the graph can be generated only after correction. See [Loop Detection](loop-detection.md).

### Unknown stream

The diagnostic `Stream 'dst' reads from 'absent', which is not defined in the plan` means that no producer with that name exists anywhere in the plan. Check the spelling and add the missing declaration or query. A `SELECT` may refer to a producer defined further down in the file as long as the dependencies are acyclic; moving an existing definition alone fixes neither a missing producer nor a cycle. Separate ordering rules apply to `LET`/`VAR`, whose declarations precede their uses, and to `RULE`, whose target must already exist when parsed. See [Syntax and Compilation Errors](../query-language-construction/syntax-and-compilation-errors.md#stream-names-fields-and-dependencies) for the diagnostics.

### Different input widths with `[_]`

The expression `core0[_] * core1[_]` expands to the minimum flat width contributed by its two arguments to the `FROM` clause; equal widths are not required. Inputs with two positions and one position produce one output field. A numeric array occupies as many positions as it has elements, while `STRING[N]` occupies one; each source's contribution is determined in the actual `FROM` tree after accounting for windows and reducers. Check the schema and `FROM` clause if fewer results appear than expected. A name outside `FROM`, or a contribution that is not a contiguous block of fields, is refused rather than assigned a default width. See [Underscore Symbol Processing](underscore-symbol-processing.md).

### Data file unavailable

This error **does not appear with `-c`** - the flag verifies the query's correctness, it does not check whether the data files exist. A source-access error can occur during normal startup, reset validation, or ad hoc import. Do not confuse it with a missing `.rql` file, which also prevents compilation.

## When Compilation Passes but Startup Fails

Source and storage state checks run before processing starts, including validation of a new plan through reset and new streams through ad hoc import. `-c` skips these checks so a plan can be compiled on a machine without its data.

| Diagnostic fragment | What to check |
| --- | --- |
| `source file does not exist`, `cannot inspect source`, `cannot read source` | The path and permissions of the account running the engine. Relative paths depend on the process working directory. |
| `not a regular file`, `not a character device or FIFO` | Whether `BINFILE`/`TEXTFILE` or `DEVICE` matches the actual source kind. |
| `directory ... from the STORAGE directive does not exist`, `is not a directory` | The `STORAGE` value or configured directory. The engine does not create this directory. |
| `descriptor schema mismatch`, `was written for TYPE`, `was written for source` | Whether the retained `.desc` matches the current schema, source kind, and path. Establish whether the intent is to continue existing data or start a new stream. |
| `rotation counter file ... is unreadable`, `cannot be read` | Counter contents and read access. A valid value is in `0..INT_MAX-1`; deleting the file restarts numbering at zero and can overwrite `.old<N>` archives. |
| `dataModel: stream '...': ... open-files limit RLIMIT_NOFILE is ...` | The process open-files limit. The diagnostic gives the soft limit, hard limit, and stream count. Check `ulimit -n` or the service unit's limits. |

Establish the effect on retained data before removing descriptors or the rotation counter. See [Runtime Errors](../query-execution/runtime-errors.md) for the complete catalogue of startup-refusal causes and effects.

### History Memory and Shared Memory

`Plan keeps ... bytes of stream history in memory; the budget [limits] history_memory_mib = ...` is a compiler refusal. Reduce record widths and history required by windows or shifts; check the largest stream contribution named in the diagnostic. This resource is separate from IPC queues.

The `-c` mode also checks whether shared memory can hold the instance's fixed reservation. A valid plan can therefore end with `shared memory too small: fixed reservation needs ..., only ... free (see -c --shmbudget)` and `ENOBUFS` (`105` on Linux). Obtain the budget report separately:

```bash
xretractor -c --shmbudget query.rql >shm-budget.txt
```

`--shmbudget` requires successful compilation, prints a report instead of a plan, and does not refuse solely because space for the fixed reservation is insufficient. The report helps assess IPC cost; it does not confirm file availability or that every subscription can start.

## Warnings and Defect Reports

`warning: ... is declared but never used`, `TIMEOUT ... is longer than the interval`, the deprecated `FILE` notice, and `grows without bound on disk` are not compilation refusals. The exit code determines success. Unused names and excessive `TIMEOUT` values are reported even without `-v`; warnings about deprecated `FILE` sources and unbounded storage growth are printed to stderr with `--verbose`. Some log entries depend on the build configuration; a missing entry does not prove the absence of a problem.

Include a minimal RQL file, the exact command, exit code, both output files, and the output of `xretractor --build-info` in a defect report. For a startup-only problem, also preserve the TOML used, working directory, relevant descriptors, and server log; remove confidential data from the copy. The `Log:` line in `xretractor --help` identifies the log location. For a service, also inspect its journal. For ad hoc failures, record the submitted statement, instance name, and client response, since the parser's detailed `msg:` goes to the server's stderr.
