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

Disabling an optimization can intentionally change the plan structure, the
result prefix, or the behavior of a known execution case. Such a result must
not automatically be classified as an unrelated regression.

CTest assigns `requires_*` labels to tests that need a specific optimization
and can disable them for an incompatible configuration. Known, confirmed
behavioral differences receive the `expected_ablation_failure` label; a test
can also have the `WILL_FAIL` property.

Use the following procedure to assess a failure:

1. run the same test in the production configuration;
2. confirm that it passes with the required optimizations;
3. run it in the variant being studied;
4. demonstrate that the failure is caused by the disabled switch;
5. only then record it as an expected ablation difference or disable the test
   for that variant;
6. treat every other failure as a regression.

The `it_optimizer_ablation-build-info` test verifies that the information
reported by the binary matches the CMake configuration. The other
`it_optimizer_ablation-*` tests check plan structures and semantic comparisons
between variants.

### Result matrix relative to the non-ablation configuration

The baseline is the non-ablation configuration: all four optimizations are
enabled and the probe is disabled. No absolute test count is recorded because
the test suite can change over time.

The table uses the following abbreviations:

- `D` — substrate deduplication;
- `S` — equivalent `SELECT` computation sharing;
- `C` — commutative-add canonicalization;
- `F` — matched hash/time-move factorization.

The “success Δ (expected/actual)” column contains two differences relative to
the non-ablation configuration:

- the first number is the change expected from the `DISABLED` and `WILL_FAIL`
  properties;
- the second number is the change observed during a full CTest run.

For example, `-2/-2` means two fewer successes were expected and two fewer were
observed, while `+1/+1` means one additional success. A mismatch such as
`-2/-3` would identify one unexpected failure. A test with the `WILL_FAIL`
property is still a CTest success when its command fails as expected.

| Active | Variant | D | S | C | F | Success Δ (expected/actual) |
| ---: | --- | :---: | :---: | :---: | :---: | ---: |
| 0 | `all_off` | OFF | OFF | OFF | OFF | -9/-9 |
| 1 | `dedup_only` | ON | OFF | OFF | OFF | -4/-4 |
| 1 | `share_only` | OFF | ON | OFF | OFF | -9/-9 |
| 1 | `factor_only` | OFF | OFF | OFF | ON | -6/-6 |
| 2 | `dedup_share` | ON | ON | OFF | OFF | -4/-4 |
| 2 | `dedup_factor` | ON | OFF | OFF | ON | -1/-1 |
| 2 | `share_comm` | OFF | ON | ON | OFF | -8/-8 |
| 2 | `share_factor` | OFF | ON | OFF | ON | -6/-6 |
| 3 | `dedup_share_comm` | ON | ON | ON | OFF | -3/-3 |
| 3 | `dedup_share_factor` | ON | ON | OFF | ON | -1/-1 |
| 3 | `share_comm_factor` | OFF | ON | ON | ON | -5/-5 |
| 4 | `all_on` | ON | ON | ON | ON | 0/0 |

Every observed result matches its expectation. The differences come from
disjoint test requirements: disabling `D` removes five successes, disabling
`F` removes three, and not having both `S` and `C` active removes one. The
values can therefore be added without referring to a fixed test-suite size.

Known execution differences marked with `WILL_FAIL` do not change the success
count: without `F`, a different factorization-case result is expected; when
`D`, `F`, and `S` are all disabled, an additional zero-valued prefix record is
expected.

## Packaging

Prepare production packages only after a successful, verified `release`:

```bash
scripts/buildrdb.sh release package
```

The `package` option restores the production switch values and rebuilds the
selected directory before running CPack. Do not run packaging from
`Release-Ablation` or `Release-Probe` directories.
