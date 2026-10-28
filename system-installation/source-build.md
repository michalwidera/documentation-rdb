# Building from Source

## Building and installing from source

Linux builds use Conan 2, CMake, and Ninja. A C++23 compiler with `<print>` and `std::println` is required (GCC 14 or newer). The project's toolchain requires CMake 4.4.2 or newer. The `scripts/buildrdb.sh` script prepares the tools and Conan profile; dependency installation on Linux uses apt.

From the downloaded `retractordb` repository:

```bash
scripts/buildrdb.sh toolchain
scripts/buildrdb.sh conan ninja
scripts/buildrdb.sh bashrc
```

After adding `~/.local/bin` to `PATH`, refresh the shell, for example by opening a new terminal. To build and install Debug:

```bash
scripts/buildrdb.sh debug
cmake --install build/Debug
ctest --test-dir build/Debug --output-on-failure
```

Installation is a separate step after building and does not require sudo by default. Integration tests also use installed programs, so installation precedes testing. The optional API libraries have [separate installation and test targets](../appendices/stream-monitoring-api.md).

A production release from source requires a clean Git tree:

```bash
scripts/buildrdb.sh release
cmake --install build/Release
ctest --test-dir build/Release --output-on-failure
```

The `release-dirty` mode is for diagnosing local changes and does not produce a production release. See the [build contract](../appendices/production-builds-and-research-variants.md). Packages for distribution are prepared separately; scripts and checks for Linux releases are described in the code repository's `scripts/release_package/README.md`.

## Engine error-handling check

The default `RDB_NOEXCEPT_CHECK=ON` adds the `rdb_noexcept_check`, `retractorcore_noexcept_check` and `rdbembed_noexcept_check` targets to a full build. They check the same core sources again with `-fno-exceptions` and `-fsyntax-only`, excluding designated units that handle ANTLR, Boost.Stacktrace and configuration. Using `throw`, `try` or `catch` in the checked part of the core then fails compilation. The check covers the compiler's syntactic and semantic analysis without generating machine code.

The `cmake/syntaxOnly.sh` script adds `-fsyntax-only` to the compiler command while preserving the configured ccache launcher. Only after success does it create the empty output file specified by `-o`, so Ninja can recognize a completed check. The targets remain `OBJECT` libraries in CMake, but their empty files are not linked into shipped programs; Release IPO is disabled for these targets.

Shipped programs and the Python module compile uniformly with exception support. External libraries still use exceptions; mixing units with and without `-fno-exceptions` in one program caused incompatible Boost and spdlog inline functions and skipped destructors when an exception crossed the core. `RDB_NOEXCEPT_CHECK` therefore replaces the original `RDB_NO_EXCEPTIONS` from port #511.

C++ core operations report recoverable errors through `rdb::Result<T> = std::expected<T, Error>`, carrying the category, message and `errno`. Callers check the result, and object construction can require a `create` or `make` factory. `RDB_NOEXCEPT_CHECK=OFF` disables only the additional compilation check; it does not restore the former exception-based C++ API. It does not control kernel survival: `rdb::fatal()` terminates the host regardless of this flag. See the [Python API error boundary](../appendices/python-jupyter-api.md#errors).

A full build runs the check automatically. Building only a selected target, such as `_core`, does not run the independent check targets; they can be built explicitly following the [Python procedure](python-build.md#module-from-a-build-tree). The `exception_mode_guard` test checks actual shipped-target flags and check completeness using `compile_commands.json`. It does not prove that the check build ran.

## Apple development environment

The macOS port is for development and testing. The system's general contract, service description, and production procedures in this manual apply to Linux. The `curl` installer described under [Linux releases](linux-releases.md) supports Linux; Apple requires a source build.

The tested port configuration is Apple silicon with macOS 27 and Apple clang 21. Intel Macs and older system releases remain unverified. Xcode 16.3+ Command Line Tools and a macOS 14.4+ deployment target are minimum requirements imposed by `std::print`, not a declaration that all such configurations have been tested.

Before building, prepare the Command Line Tools (`xcode-select --install`), Homebrew, and CMake, Python 3, and Git available on `PATH`. On macOS, `scripts/buildrdb.sh toolchain` uses Homebrew. The script below can install missing Conan and Ninja through Homebrew; it also uses the Conan environment to provide the required CMake version:

```bash
scripts/macos-build.sh
scripts/macos-build.sh --sanitize
```

The default run is Debug: configure, build, install, refresh the test copy, rebuild, run CTest, and run the separate `test-api` target. The log is written to `build/macos-build.log`. `--sanitize` enables AddressSanitizer and UndefinedBehaviorSanitizer. `--no-install` disables automatic tool installation, but still installs the built programs. `--skip-tests` skips tests while retaining installation. `scripts/macos-build.sh release` selects the Release configuration but does not perform the checks of the production `scripts/buildrdb.sh release` workflow.

### Differences relevant to development

| Area | macOS port behavior |
| --- | --- |
| Configuration | Without `--config`, layers are read in order from `/etc/retractor/retractor.toml`, `/usr/local/etc/retractor/retractor.toml`, `/opt/homebrew/etc/retractor/retractor.toml`, then the user location. Later layers override earlier keys. The Homebrew path does not imply that an installation formula is available. |
| IPC | Boost.Interprocess uses file-backed storage under `/tmp/boost_interprocess/...`; `--shmbudget` reports that volume rather than Linux's `/dev/shm` tmpfs. Overlong object names receive a deterministic shortened token; the public server name retains its 32-character limit. |
| Process liveness | `sysctl` provides the PID and start time; the absence of `/proc` does not remove the live-owner check. The bus lock has a fallback that recovers after its owner's death. |
| Real time | `SCHED_FIFO` is set on the processing thread through `pthread_setschedparam`. The TOML priority (1..99) is clamped to the kernel's range. CPU affinity and a PREEMPT_RT equivalent are unavailable; `mlockall` can return `ENOSYS`, after which execution continues without locked memory pages. Absolute sleep uses the Mach interface. This is not a measurement platform for Linux real-time guarantees. |
| Service | The code identifies a launchd job through `XPC_SERVICE_NAME` and parent PID 1, and builds a restart command using `launchctl kickstart -k`. Choosing the domain from the effective UID is a heuristic: a system daemon running as a non-root user may receive the wrong domain. The package provides neither a `.plist` nor a launchd service installer. |
| Memory tests | On Apple silicon, tests run without Valgrind. Run memory checks in a separate sanitizer configuration; passing ordinary CTest, including entries with `-vg` in their names, does not establish that such checks ran. |
| API | The script explicitly runs `test-api`, covering Python and C++ clients and process creation. The API remains optional; this development path does not extend the production API contract to macOS. |
| Packaging | CPack creates TGZ without the systemd service component. The ability to create a Darwin archive locally does not mean it is available through the web installer. |

Platform capability checks and fallback declarations are described in the [build appendix](../appendices/production-builds-and-research-variants.md#platform-capabilities-and-sanitizers).
