# Production Builds and Diagnostic Variants

The `scripts/buildrdb.sh` script provides the production `release` build and diagnostic modes. The `release-ablation` and `probe` variants have separate CMake configurations, output directories, and Conan generators. Verification of the resulting binary confirms its switches. Tool preparation and installation are described in [Installation Process](installation-process.md).

> **⚠️ Warning**
>
> Binaries produced by `release-dirty`, `release-ablation`, and `probe` are diagnostic variants. They must not be installed or packaged as production releases.

## Build modes

| Command | Purpose | Binary directory |
| --- | --- | --- |
| `scripts/buildrdb.sh release` | verified production release | `build/Release` |
| `scripts/buildrdb.sh release-dirty` | diagnostics of local changes, without production qualification | `build/Release` |
| `scripts/buildrdb.sh release-ablation` | selected optimizer and probe configuration | `build/Release-Ablation/<configuration>` |
| `scripts/buildrdb.sh probe` | diagnostics with the probe enabled | `build/Release-Probe` |

The `release-ablation` and `probe` modes also use separate Conan generator directories:

- `build/Conan-Release-Ablation/<configuration>`,
- `build/Conan-Release-Probe`.

Consequently, their CMake cache, compiler definitions, and binaries are not written to the production `build/Release` directory.

`release-dirty` accepts uncommitted changes and rebuilds the same `build/Release` directory used by `release`. It still sets the optimizer switches explicitly and checks `--build-info`, but the result is for diagnosing changes before a commit. It is neither an isolated variant nor a production release; run `release` again from a clean tree before preparing a release.

## The production `release` contract

The command:

```bash
scripts/buildrdb.sh release
```

operates in a *fail-closed* mode: every failed check stops the build. The script:

1. requires a Git repository and a completely clean working tree;
2. rejects tracked changes, staged changes, and untracked files;
3. removes the previous `build/Release` directory;
4. removes common variables that can inject compiler, linker, or CMake flags from the configuration process;
5. explicitly passes the complete production configuration;
6. builds the binary in a fresh directory;
7. reads the configuration from the resulting `xretractor`;
8. checks the source tree again after the build.

Variables removed from the build process environment include `CFLAGS`, `CPPFLAGS`, `CXXFLAGS`, `LDFLAGS`, `CMAKE_ARGS`, `CMAKE_GENERATOR`, and `CMAKE_TOOLCHAIN_FILE`. The probe runtime variables `RDB_BENCH_CSV` and `RDB_BENCH_PLAN` are not passed either.

The production configuration is always:

```text
RDB_OPT_DEDUP_SUBSTRATES=ON
RDB_OPT_SHARE_EQUIVALENT_SELECTS=ON
RDB_OPT_COMMUTATIVE_ADD=ON
RDB_OPT_FACTOR_MATCHED_HASH_TIMEMOVES=ON
RDB_BENCH_PROBE=OFF
RDB_OPT_SIMPLIFY_EXPRESSIONS=ON
```

After compilation, the script runs:

```bash
build/Release/src/retractor/xretractor --build-info
```

and compares the result with the set above. A missing binary or any different value causes `release` to fail.

> **ℹ️ Info**
>
> The Git cleanliness check proves that the build does not use local, uncommitted changes. It does not prove that the contents of a committed revision are correct. Review, tests, and CI are responsible for that part.

## Variants with disabled optimizations

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
RDB_OPT_SIMPLIFY_EXPRESSIONS
```

Each variant receives a directory that describes its complete configuration, for example:

```text
build/Release-Ablation/dedup-OFF_share-ON_comm-ON_factor-ON_probe-OFF_simplify-ON
```

All six values are passed explicitly. This prevents values stored by an earlier configuration in `CMakeCache.txt` from being inherited.

The configuration:

```text
RDB_OPT_SHARE_EQUIVALENT_SELECTS=OFF
RDB_OPT_COMMUTATIVE_ADD=ON
```

is invalid. Commutative-add canonicalization is part of equivalent `SELECT` computation sharing, so both the submenu and CMake reject this combination.

After building a variant, the script compares `--build-info` with the values selected in the submenu. A mismatch is a configuration error.

## Diagnostic probe

`RDB_BENCH_PROBE` is optional instrumentation rather than a plan optimization. The command:

```bash
scripts/buildrdb.sh probe
```

builds a variant with all optimizations enabled and:

```text
RDB_BENCH_PROBE=ON
```

The binary is written to `build/Release-Probe`. It is built from optimized `Release` code, but the resulting binary is not a production build.

In `release-ablation`, the probe can be enabled or disabled independently of a valid optimizer configuration.

The probe does not participate in the selection or order of optimizer passes. It is not zero-cost instrumentation, however: `RDB_BENCH_PLAN` additionally traverses the plan and writes statistics, while `RDB_BENCH_CSV` performs clock measurements and file operations. The probe is therefore semantically non-invasive, but its overhead can affect measured timings.

When the binary has `RDB_BENCH_PROBE=ON` and `RDB_BENCH_PLAN` is set during compilation, the compiler writes the following stable line to standard error:

```text
REWRITE_APPLIED r1=<count> r2=<count> r3=<count>
```

The counters are reset before every compiler invocation. `r1` is the number of successful `(A > i) # (B > k) -> (A # B) > (i + k)` rewrites. `r2` is the number of unique `STREAM_ADD` nodes for which the canonical plan fingerprint actually swapped the children. `r3` is the number of simplifications in field programs and `RULE` conditions: constant folds, combined constant tails, removed neutral elements, and replacements of a repeated exact factor by a power (`E*E*E -> E^3`). That last rule covers only the `BYTE`, `INTEGER`, `UINT`, and `RATIONAL` types; it does not rewrite `FLOAT` or `DOUBLE` multiplication. The counters describe applied rewrites, not speedup. With `RDB_BENCH_PROBE=OFF`, the counter code is absent from the binary and no `REWRITE_APPLIED` line is emitted.

## Inspecting a variant manually

Every `xretractor` provides:

```bash
path/to/xretractor --build-info
```

The command prints the configuration and exits without starting the engine (`-b` is an equivalent shorthand). It is handled before the configuration file is loaded and validated, so it yields a correct result even when the host configuration would prevent the program from starting normally. An example production result is:

```text
RDB_OPT_DEDUP_SUBSTRATES=ON
RDB_OPT_SHARE_EQUIVALENT_SELECTS=ON
RDB_OPT_COMMUTATIVE_ADD=ON
RDB_OPT_FACTOR_MATCHED_HASH_TIMEMOVES=ON
RDB_BENCH_PROBE=OFF
RDB_OPT_SIMPLIFY_EXPRESSIONS=ON
```

The directory name is only a convenience; the information read from the binary is the final confirmation of the compiler definitions used.

## Variant tests

Disabling an optimization can intentionally change plan structure and the availability of tests that require a particular shape. It must not change the value part of the result: interval, logical origin, public descriptor, records with null maps, or materialization policy. The startup tail has the weaker guarantee described below.

CTest assigns `requires_*` labels to tests that need a specific optimization and can disable them for an incompatible configuration. The `expected_ablation_failure` label then describes the expected unavailability of a plan-shape test, not permission for semantic divergence.

Use the following procedure to assess a failure:

1. run the same test in the production configuration;
2. confirm that it passes with the required optimizations;
3. run it in the variant being studied;
4. demonstrate that the failure is caused by the disabled switch;
5. if the test requires the disabled pass, disable it for that variant;
6. treat every other failure as a regression.

The `it_optimizer_ablation-build-info` test verifies that the information reported by the binary matches the CMake configuration. The other `it_optimizer_ablation-*` tests check plan structures and semantic comparisons between variants.

A variant with an optimization disabled may change plan structure, but it must not change values, `NULL` maps, the public descriptor, logical origin, or materialization policy. A correct plan rewrite may shorten the tail, but it must not cause emission before the data is available. Any other divergence is a regression, not an admissible property of a variant.

## Packaging

Prepare production packages only after a successful, verified `release`:

```bash
scripts/buildrdb.sh release package
```

The `package` option restores the production switch values and rebuilds the selected directory before running CPack. Do not run packaging from `Release-Ablation` or `Release-Probe` directories.

Packages serve different purposes:

| Variant | Default contents and paths |
| --- | --- |
| Linux: `package` (DEB/TGZ) | Three programs under `/usr/bin`, a systemd unit, license, default TOML, and configuration examples. |
| Linux: `package-portable` | Relative paths: `bin/`, `share/doc/retractordb/LICENSE`, `share/retractordb/retractor.toml`; no systemd unit. The web installer can create the service. |
| Apple development port: `package` (TGZ) | `/usr/local` prefix, without the systemd service component; no launchd configuration is supplied. |

CPack does not generate a source package. The `it_packaging` test checks the exact contents of the DEB when `dpkg-deb` is available, and of the portable archive. Scripts for preparing Linux release assets live in `scripts/release_package/`; running them and publishing assets are separate from local installation.

## Platform capabilities and sanitizers

CMake configuration checks the available platform functions and records `RDB_HAS_*` results in `generated/platformConfig.h`. The `RDB_PLATFORM_FALLBACKS` list specifies deliberately allowed fallback paths. It is empty by default on Linux. If a controlled probe selects an undeclared fallback, configuration fails; inspect `CMakeFiles/CMakeConfigureLog.yaml` before adding a missing function to the list.

The CMake option `-DRDB_SANITIZE=address,undefined` enables AddressSanitizer and UndefinedBehaviorSanitizer; detected undefined behavior terminates execution. This is a CMake configuration argument, not an additional `buildrdb.sh` option. Sanitizers require rebuilding the binaries under test.

On the Apple development port, the ready-made entry point is `scripts/macos-build.sh --sanitize`. Running ordinary tests without Valgrind does not enable sanitizers automatically. `scripts/macos-build.sh release` selects the Release configuration but does not implement the production contract of `buildrdb.sh release`. See [Apple development environment](installation-process.md#apple-development-environment) for the full workflow and limitations.

## Optional client API

The `api/` directory is developed and tested with the engine, but it is not part of the default product. Plain `ninja`, `ninja install`, `ninja test`, and `ninja package` leave the API libraries and tests out of their results.

The explicit entry points are separate:

| Command | Meaning |
| --- | --- |
| `ninja install-withapi` | Builds and installs the engine and the `api` component. |
| `ninja test-api` | Builds the C++ test client and runs tests carrying the `api` label. |
| `cmake -DRDB_WITH_API=ON .` | Adds the `api` component to CPack packages; the ordinary `test` target then stops filtering out the `api` label. |

The packaging switch must be set during configuration because CPack determines its component list at that point. Without `RDB_WITH_API=ON`, packages contain no API libraries; their remaining contents depend on the package variant described above. The `it_packaging` test protects the default Linux DEB and portable contents.

C++ API targets are always known to CMake, but use `EXCLUDE_FROM_ALL`. Their installation rules belong to the separate `api` component, so `ninja install` alone does not run them. Library usage and the JSONL contract are described in [Stream Monitoring API](stream-monitoring-api.md).
