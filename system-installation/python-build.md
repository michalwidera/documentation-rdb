# Building the Python Library

Run these commands in the `retractordb` repository. An ordinary engine build does not build the extension: explicit `RDB_PYTHON=ON` adds `_core` and only then searches for Python and nanobind. Linux and macOS are supported hosts; requesting the flag on another host fails configuration. `RDB_IOS` and `RDB_ANDROID` are reserved names without implementations. Embedded-consumer flags default to OFF, look up dependencies only when enabled, name the consumer rather than the host, and reject unsupported hosts.

## Module from a build tree

Install the [engine build dependencies](source-build.md), CPython 3.10+ with headers, and nanobind importable by the selected interpreter. Use Python 3.12 for reproducible Jupyter profiles. A venv keeps build tools out of a system Python covered by PEP 668:

```bash
scripts/python-venv.sh --python python3.12 --venv .venv-python312
cmake -S . -B build/Debug-Python -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$PWD/build/Debug/generators/conan_toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Debug -DRDB_PYTHON=ON \
  -DPython_EXECUTABLE="$PWD/.venv-python312/bin/python3"
cmake --build build/Debug-Python --target _core --parallel 4
```

This example requires a compatible existing Conan build in `build/Debug`, including its toolchain and dependencies; it does not create a Conan profile. Without that build, first follow [building from source](source-build.md). To clear discovery of a previous interpreter in an existing separate `build/Debug-Python`:

```bash
cmake -S . -B build/Debug-Python -U '_Python_*' -U nanobind_DIR \
  -DRDB_PYTHON=ON -DPython_EXECUTABLE="$PWD/.venv-python312/bin/python3"
cmake --build build/Debug-Python --target _core --parallel 4
```

Do not run `cmake .` in the repository root. The interpreter is cached. The module and copied `.py` files go to `<build>/python/retractordb`; the cache records this directory as `RDB_PYTHON_MODULE_DIR`. Importing from the build needs no `ninja install`. Nanobind uses `Python::` targets and the ordinary module uses `Development.Module` without linking libpython. The abi3 build selects `Development.SABIModule`.

`scripts/python-venv.sh` installs nanobind, NumPy, pytest, clang-format 21.1.7 and cmakelang. It omits torch; complete [Jupyter profiles](python-jupyter.md) prepare it separately. The script is idempotent; `--python`, `--venv`, `--recreate` and `--print-python` select the interpreter, directory, recreation and path-only output. CMake also runs the `python -m nanobind --cmake_dir` probe.

Formatters are called by name and need the venv on PATH:

```bash
PATH="$PWD/.venv-python312/bin:$PATH" ninja -C build/Debug cformat
```

When building only `_core`, the additional [core check](source-build.md#engine-error-handling-check) is not its dependency. With the default `RDB_NOEXCEPT_CHECK=ON`, run it through a full build or explicitly:

```bash
cmake --build build/Debug-Python \
  --target rdb_noexcept_check retractorcore_noexcept_check rdbembed_noexcept_check \
  --parallel 4
```

This check changes neither the module flags nor the [Python error boundary](../appendices/python-jupyter-api.md#errors). Building or importing `_core` alone does not prove that the additional compilation ran.

## Tests and module provenance

```bash
RDB_PYTHON_MODULE_DIR="$PWD/build/Debug-Python/python" \
  .venv-python312/bin/python3 -m pytest api/python/tests
```

Without an explicit variable, tests search the first sorted `build/*/python` containing `_core`; a missing module produces skips. Those skips do not establish acceptance. Full #451 acceptance also needs torch and freshly built `xretractor` and `xqry`; `RDB_XRETRACTOR` must select the correct program. Explicitly setting both variables turns missing dependencies or a missing reference binary into failures. Before reporting a result, check the imported `_core` path, package-copy equality with source, and the executable selected in the test environment.

`RDB_PYTHON=ON` enables PIC for the static libraries linked into `_core`: `rdb`, `descparser`, `common`, `retractorcore`, `rqlparser` and `rdbembed`. Apart from `rdbembed`, the same libraries go into `xretractor`, `xqry` and `xtrdb`, so on Linux x86_64 this also changes the engine binaries in that build. Comparative measurements, the research gate and ablation belong in a separate build with `RDB_PYTHON=OFF`. On arm64 Darwin, PIC does not change this aspect of the generated code.

## Sanitizers

Use a separate build without `RDB_SANITIZE` for ordinary Jupyter. Loading an ASan module with `dlopen` can terminate import unless the runtime was loaded first. Sanitized module tests need explicit preloading; `asan-build` denotes an existing sanitizer build:

```bash
# Linux / GCC; Python is a C program, so preload libstdc++ too.
LD_PRELOAD="$(g++ -print-file-name=libasan.so) $(g++ -print-file-name=libstdc++.so)" \
ASAN_OPTIONS=detect_leaks=0 RDB_PYTHON_MODULE_DIR=asan-build/python \
  .venv-python312/bin/python3 -m pytest api/python/tests

# macOS / Apple clang
DYLD_INSERT_LIBRARIES="$(clang -print-resource-dir)/lib/darwin/libclang_rt.asan_osx_dynamic.dylib" \
ASAN_OPTIONS=detect_container_overflow=0 RDB_PYTHON_MODULE_DIR=asan-build/python \
  .venv-python312/bin/python3 -m pytest api/python/tests
```

These variants disable LSan or container-overflow checks respectively; report that scope. C++ tests disable container-overflow by default to avoid false alarms when instrumented libc++ vectors mix with unsanitized GoogleTest. Other ASan checks remain enabled; `ASAN_OPTIONS=detect_container_overflow=1` restores that check. Ordinary pytest does not replace memory checks.

## Manylinux image and wheel build

`docker/wheel/Dockerfile` extends a pinned PyPA manylinux_2_28 image with valgrind, a tools venv containing Conan, CMake >= 4.4.2 and Ninja, and a Release cache in `/opt/conan`. `RDB_USE_MOLD=OFF` selects an available linker. x86_64 and aarch64 use the same Dockerfile; its header records base-image digests. Conan dependencies, including tools, build inside the image to avoid importing newer glibc requirements.

```bash
docker build --platform linux/amd64 --build-arg RDB_VERSION="$(cat VERSION)" \
  -f docker/wheel/Dockerfile \
  -t micwide/buildenv-retractordb-wheel:manylinux_2_28_x86_64 .
docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" \
  micwide/buildenv-retractordb-wheel:manylinux_2_28_x86_64 \
  bash /src/docker/wheel/smoke.sh
```

`toolchain-probe.cpp` checks C++23 library requirements. `audit-so.py` uses `auditwheel show --json`, rejects glibc requirements above the image policy and libraries outside that policy. It also checks the absence of `bus`, `ipcServer`, `serverName`, `lockManager` and `shmBudget` code; a linker map supplements the stripped Release-module check.

`smoke.sh` copies sources into the container with the host mounted read-only, checks the cache with `--build never`, builds `_core`, audits it and runs Python tests with explicit module provenance. `jobs.sh` limits parallelism to one job per 2 GiB, respecting cgroups.

The root `pyproject.toml` uses scikit-build-core and the version from `VERSION`, builds only `_core`, installs the `python` component and includes `api/python/retractordb` files. NumPy is a runtime dependency and torch is optional. `api/python/pyproject.toml` remains a client installation without compilation; both distributions are named `retractordb` and replace each other in one venv.

```bash
pipx install cibuildwheel
docker/wheel/build-wheels.sh x86_64
```

The argument can also be `aarch64` or `all`. The script copies the checkout without ignored artifacts and writes wheels to `build/wheelhouse/`. It uses locally tagged images; publishing them is a separate decision. It builds CPython 3.10, 3.11 and one `cp312-abi3` wheel for 3.12+. cibuildwheel repairs the manylinux tag, runs `abi3audit --strict` and tests installed wheels with explicit `_core` and `RDB_PYTHON_MODULE_DIR`. Torch and the reference executable can be absent in this configuration; skips are not full #451 acceptance.

`EXCLUDE_FROM_ALL` keeps `_core` out of ordinary `ninja install`, and the CPack component list excludes `python`. Building wheels neither publishes to PyPI nor automatically performs [Colab acceptance](../appendices/notebook-acceptance.md). macOS wheels, publication CI and ingest remain separate stages.
