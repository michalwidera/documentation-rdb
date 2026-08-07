# Production Builds and Research Variants

The `scripts/buildrdb.sh` script separates production builds from compilations
used for optimizer studies and performance measurements. The separation covers
the CMake configuration, output directories, Conan generators, and verification
of the resulting binary.

> **⚠️ Warning**
>
> Binaries produced by `release-ablation` and `probe` are research artifacts.
> They must not be installed or packaged as production releases.

## Build modes

| Command | Purpose | Binary directory |
| --- | --- | --- |
| `scripts/buildrdb.sh release` | verified production release | `build/Release` |
| `scripts/buildrdb.sh release-ablation` | selected optimizer and probe configuration | `build/Release-Ablation/<configuration>` |
| `scripts/buildrdb.sh probe` | measurements with the probe enabled | `build/Release-Probe` |

The research modes also use separate Conan generator directories:

- `build/Conan-Release-Ablation/<configuration>`,
- `build/Conan-Release-Probe`.

Consequently, their CMake cache, compiler definitions, and binaries are not
written to the production `build/Release` directory.

## The production `release` contract

The command:

```bash
scripts/buildrdb.sh release
```

operates in a *fail-closed* mode: every failed check stops the build. The
script:

1. requires a Git repository and a completely clean working tree;
2. rejects tracked changes, staged changes, and untracked files;
3. removes the previous `build/Release` directory;
4. removes common variables that can inject compiler, linker, or CMake flags
   from the configuration process;
5. explicitly passes the complete production configuration;
6. builds the binary in a fresh directory;
7. reads the configuration from the resulting `xretractor`;
8. checks the source tree again after the build.

Variables removed from the build process environment include `CFLAGS`,
`CPPFLAGS`, `CXXFLAGS`, `LDFLAGS`, `CMAKE_ARGS`, `CMAKE_GENERATOR`, and
`CMAKE_TOOLCHAIN_FILE`. The probe runtime variables `RDB_BENCH_CSV` and
`RDB_BENCH_PLAN` are not passed either.

The production configuration is always:

```text
RDB_OPT_DEDUP_SUBSTRATES=ON
RDB_OPT_SHARE_EQUIVALENT_SELECTS=ON
RDB_OPT_COMMUTATIVE_ADD=ON
RDB_OPT_FACTOR_MATCHED_HASH_TIMEMOVES=ON
RDB_BENCH_PROBE=OFF
```

After compilation, the script runs:

```bash
build/Release/src/retractor/xretractor --build-info
```

and compares the result with the set above. A missing binary or any different
value causes `release` to fail.

> **ℹ️ Info**
>
> The Git cleanliness check proves that the build does not use local,
> uncommitted changes. It does not prove that the contents of a committed
> revision are correct. Review, tests, and CI are responsible for that part.

## Ablation variants

The command:

```bash
scripts/buildrdb.sh release-ablation
```

opens a submenu that independently toggles:

```text
RDB_OPT_DEDUP_SUBSTRATES
RDB_OPT_SHARE_EQUIVALENT_SELECTS
RDB_OPT_COMMUTATIVE_ADD
RDB_OPT_FACTOR_MATCHED_HASH_TIMEMOVES
RDB_BENCH_PROBE
```

Each variant receives a directory that describes its complete configuration,
for example:

```text
build/Release-Ablation/dedup-OFF_share-ON_comm-ON_factor-ON_probe-OFF
```

All five values are passed explicitly. This prevents values stored by an
earlier configuration in `CMakeCache.txt` from being inherited.

The configuration:

```text
RDB_OPT_SHARE_EQUIVALENT_SELECTS=OFF
RDB_OPT_COMMUTATIVE_ADD=ON
```

is invalid. Commutative-add canonicalization is part of equivalent `SELECT`
computation sharing, so both the submenu and CMake reject this combination.

After building a variant, the script compares `--build-info` with
the values selected in the submenu. A mismatch is a configuration error, not
an ablation-study result.

## Measurement probe

`RDB_BENCH_PROBE` is measurement instrumentation rather than a plan
optimization. The command:

```bash
scripts/buildrdb.sh probe
```

builds a variant with all optimizations enabled and:

```text
RDB_BENCH_PROBE=ON
```

The binary is written to `build/Release-Probe`. The probe is intended for
measurements on optimized `Release` code, but the resulting binary is not a
production build.

In `release-ablation`, the probe can be enabled or disabled independently of a
valid optimizer configuration. This makes it possible to compare the same
variants both without and with instrumentation.

Code analysis confirms that the probe does not change the selection, order, or
result of optimizer passes. It is not zero-cost instrumentation, however:
`RDB_BENCH_PLAN` additionally traverses the plan and writes statistics, while
`RDB_BENCH_CSV` performs clock measurements and file operations. The probe is
therefore semantically non-invasive, but its overhead can affect measured
timings.

When the binary has `RDB_BENCH_PROBE=ON` and `RDB_BENCH_PLAN` is set during
compilation, the compiler writes the following stable line to standard error:

```text
REWRITE_APPLIED r1=<count> r2=<count>
```

The counters are reset before every compiler invocation. `r1` is the number of
successful `(A > i) # (B > k) -> (A # B) > (i + k)` rewrites. `r2` is the
number of unique `STREAM_ADD` nodes for which the canonical plan fingerprint
actually swapped the children. `r2` is neither the number of removed nodes nor
a speedup metric. With `RDB_BENCH_PROBE=OFF`, the counter code is absent from
the binary and no `REWRITE_APPLIED` line is emitted.

## Inspecting a variant manually

Every `xretractor` provides:

```bash
path/to/xretractor --build-info
```

The command prints the configuration and exits without starting the engine
(`-b` is an equivalent shorthand). It is handled before the configuration file
is loaded and validated, so it yields a correct result even when the host
configuration would prevent the program from starting normally. An example
production result is:

```text
RDB_OPT_DEDUP_SUBSTRATES=ON
RDB_OPT_SHARE_EQUIVALENT_SELECTS=ON
RDB_OPT_COMMUTATIVE_ADD=ON
RDB_OPT_FACTOR_MATCHED_HASH_TIMEMOVES=ON
RDB_BENCH_PROBE=OFF
```

The directory name helps organize experiments, but the information read from
the binary is the final confirmation of the compiler definitions used.

## Tests in the ablation process

Disabling an optimization can intentionally change plan structure and the
availability of tests that require a particular shape. It must not change
the observable result: interval, startup tail, public descriptor, records
with null maps, or materialization policy.

CTest assigns `requires_*` labels to tests that need a specific optimization
and can disable them for an incompatible configuration. The
`expected_ablation_failure` label then describes the expected
unavailability of a plan-shape test, not permission for semantic divergence.

Use the following procedure to assess a failure:

1. run the same test in the production configuration;
2. confirm that it passes with the required optimizations;
3. run it in the variant being studied;
4. demonstrate that the failure is caused by the disabled switch;
5. if the test requires the disabled pass, disable it for that variant;
6. treat every other failure as a regression.

The `it_optimizer_ablation-build-info` test verifies that the information
reported by the binary matches the CMake configuration. The other
`it_optimizer_ablation-*` tests check plan structures and semantic comparisons
between variants.

### Named research profiles

The K4 methodology defines five profiles that should be recorded with results:

| Profile | Deduplication | `SELECT` sharing | `+` commutativity | R1 factorization |
| --- | :---: | :---: | :---: | :---: |
| `OFF` | OFF | OFF | OFF | OFF |
| `STRUCT` | ON | ON | OFF | OFF |
| `STRUCT+R1` | ON | ON | OFF | ON |
| `STRUCT+R2` | ON | ON | ON | OFF |
| `ALGSTRUCT` | ON | ON | ON | ON |

`ALGSTRUCT` matches the default optimizer configuration. A binary's
`--build-info` remains the source of truth for its exact settings. Each
intermediate profile changes only one rule relative to `STRUCT`: `STRUCT+R1`
enables R1 factorization, while `STRUCT+R2` enables commutative `STREAM_ADD`
canonicalization.

After introducing causal startup tails, one `tau` convention, and final
topological sorting, there are no expected semantic differences between
profiles. The probe confirms for `OFF`, `STRUCT`, and the default
configuration that R1 values, null maps, absence of prefixes, and tails
agree. Two former `WILL_FAIL` cases — a different R1 result without
factorization and an extra zero-valued prefix record — were removed together
with their causes and are no longer permissible ablation outcomes.

Ablation variants exist purely for correctness control: they let you check that
disabling a single rule does not change the observable result, and that the
optimizer is not hiding a defect that would surface without it. Measurements of
the cost and performance benefit of individual rules do not belong to this
documentation — they are carried out in a separate experimental repository and
reported in a separate publication.

## Packaging

Prepare production packages only after a successful, verified `release`:

```bash
scripts/buildrdb.sh release package
```

The `package` option restores the production switch values and rebuilds the
selected directory before running CPack. Do not run packaging from
`Release-Ablation` or `Release-Probe` directories.
