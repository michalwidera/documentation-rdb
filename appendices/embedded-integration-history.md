# Embedded Integration History

This historical material covers C2/C3 of epic #446 and the initial Python binding. It replaces `core-phase-2.md`, `core-phase-3.md` and historical parts of `jupyter-integration.md` from the code repository's former `docs` directory. The current contract lives in the [Python API](python-jupyter-api.md), and commands in [building the library](../system-installation/python-build.md). #450 later introduced storage-directory ownership, and #476/#451 completed error policy and acceptance. Library real-time execution, mobile targets, ingest, DeviceWindowLoader and MPS hardware acceptance remain outside the completed epic scope.

After epic #445 was merged, port #511 replaced the historical throwing boundary with Result and the `rdb::fatal()` handler. Shipped programs use a uniform exception mode, and `RDB_NOEXCEPT_CHECK` checks the core separately. The C2/C3 descriptions below preserve those stages; the [Python API](python-jupyter-api.md#errors) describes the current recovery boundary.

## C2: instance-owned state

The daemon constructed state once, making process state difficult to distinguish from engine state. A notebook creates and destroys engines on repeated cell execution. C2 separated ownership so stream names in different instances would not cause shared results.

| State before C2 | Change or remaining scope |
| --- | --- |
| Static MEMORY record map in `faccmemory.cc` | `rdb::MemoryStore` belongs to its owner; separate instances are isolated |
| Static `Descriptor::singleLineOutput_` flag | Formatting belongs to one `std::ostream`, through an `ios_base::xalloc` slot |
| `fatalErrorRaised` | Remained part of `xretractor` termination; the throwing boundary separates embedding |
| Default spdlog logger | Launchers or the module host configure it, not an engine instance |
| Probe counters | Known process debt; measurements do not use the Python build |
| `pProc`, `core_mutex`, `esm::*` | Service state did not move into embedding; full service restructuring stayed separate |

Memory Store retained its bucket layout: data, NULL maps, write count, record size and live-user count. A stream's writer and reader still share a bucket within one Store. The `memoryFile` constructor takes `MemoryStore&`; `makeAccessor` and `storage` accept an optional pointer. Omitting it selects `MemoryStore::processDefault()`, preserving the existing service and xtrdb behavior. The last user removes the bucket; an instance with a different record size clears incompatible data. Ownership changed; the data format did not.

`ut_faccmemory` checks separate Stores with the same name, sharing within a Store, the default process Store and propagation through `storage`. Creating and destroying `Storage` alone did not establish whole-plan isolation.

Descriptor formatting had been process-wide and reset by printing. After C2, `rdb::singleLineFormat` changes stream state through `isSingleLineOutput` / `setSingleLineOutput`; it remains one-shot but does not affect another stream. The binding could remove its save/restore workaround.

The `test/embedding_boundary.py` gate preserves the boundary: forbidden process state, logger configuration and process-ending paths must not return to embedding outside explicitly controlled boundaries. This is a structural source test, not a general concurrency proof.

The first `rdb::embed::Engine` facade owned a Memory Store and opened storage through `openStorage()`. It did not execute plans yet. Probe and executor state remained debt; VOLATILE-stream isolation was established only in C3, when the Store reached the model and `streamInstance`.

## C3: host-driven plan

`retractorcore` contains the RQL parser/compiler, expressions, `query`/`qTree`, `dataModel`, `streamInstance`, rules, `dumpManager` and timeline. It was separated from the `retractor` service layer: executor with clock, terminal, IPC, bus and process configuration. `rdbembed` links the facade with `retractorcore`; `_core` does not link service libraries. DUMP rules remained in the core, but the facade refuses them because it does not publish the global `pProc` model.

A private `Plan` owns `qTree`, compiler, model, `TimeLine` and counters in dependency order, with reverse destruction order. `compile()` parses, compiles, checks storage and prepares artifacts, model and timeline. `step()` executes the ZERO-step on the first slot, selects the next timeline instant, constructs the due-stream mask and calls `dataModel::processRows` without a clock, IPC or terminal.

`untilEof` marks sources ONESHOT before model construction, like `xretractor -u`. The slot detecting EOF retains correctly computed records; the next call reports completion. No-wrap behavior was chosen for notebooks treating a file as a dataset.

The model and `streamInstance` received an optional `MemoryStore*`. The facade passes its instance Store; the service uses the default Store when no argument is supplied. `ut_embedEngine` and the two-engine Python test using the same VOLATILE name preserve that isolation.

`dumpManager::processStreamChunk` first checks its job ledger. With no jobs it needs no `pProc`; with a job, an absent model remains an internal error. The facade refuses DUMP, SYSTEM, ROTATION and DEVICE at compilation: these need the service model, would execute the host shell, require a rotation counter, or need a DEVICE reception phase absent from `step()`. No host callback authorizing SYSTEM was added.

Early C3 replaced declaration descriptors during notebook recompilation. #450 later restricted that operation to an owned, locked directory after preflight. The old note does not authorize overwriting foreign directories. #451 later added explicit missing-source refusal in embedding, while the service still produces NULL.

Facade `Refused` errors distinguished Parse, Check and Request stages. `ThrowOnFatalScope` translated K1/K4 into `EngineFatal` rather than terminating the host. A slot failure latched plan state. Later #476 and #491 established `PlanError`, multiple inheritance with `ConfigError`/`IOError`, errno and whole-module taint after K1. The historical statement that full error policy remained unfinished described C3's moment, not current behavior.

`record()` returns a copy; `project()` returns flattened double values with NaN for NULL. Declarations read model history; SELECT results read its storage. Python adds `rows`, `to_numpy`, `window` and `Window`; a window owns a NumPy array and exports its DLPack. Data does not pin engine memory, so a tensor can survive the next slot.

The GIL is released during core work. The `run()` loop periodically reacquires it for Python signals. The module sends diagnostics to the `retractordb` logger; static, hidden spdlog linking confines that configuration to the extension. C3 did not fully restructure `executorsm::run`, add a DEVICE phase or SYSTEM callback, or guarantee general concurrency; global `core_mutex` still limits parallel execution.

## Initial binding and distribution decisions

Stage 1a covered storage only, because parser, execution and process state required C2/C3. It established `FieldType`, `Field`, `Descriptor`, `Storage` and `Record` mappings, offline reads and exceptions. This experiment confirmed nanobind over pybind11. Historical measurements on macOS arm64, Apple clang, Debug, nanobind 3.1.0 and Python 3.14 recorded `module.cpp` compilation at 1.6 s cold / 0.9 s incremental and an 8.8 MB unstripped module. These describe that binding, not comparative engine performance or current wheel size.

| Roadmap stage | Scope and subsequent resolution |
| --- | --- |
| J1 | `compile`, `step`, result iteration and plan errors after C2/C3 |
| J2 | NumPy, `Window`, DLPack and IterableDataset; copies rather than engine buffers |
| J3 | KeyboardInterrupt in `run` and the `logging` bridge |
| J4 | scikit-build-core/cibuildwheel packaging and Linux manylinux; PyPI publication remains separate |
| J5 | Colab notebook and installed-wheel smoke; runtime acceptance is recorded separately |
| J6 | Python push ingest; outside the implemented scope |

Decisions: avoid a hard torch dependency that could replace an existing CUDA installation; install wheels rather than compile an sdist in Colab; export copied results rather than pin engine memory. The approximately 20 s installation reference was a roadmap goal, not an issue closure criterion. Mobile XCFramework/AAR, real-time embedding, DeviceWindowLoader and MPS hardware acceptance remain separate tasks.
