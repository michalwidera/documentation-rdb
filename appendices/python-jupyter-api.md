# Python and Jupyter API

This chapter describes the `dev/445-jupyter-epic` API accepted in #451 and the storage-directory contract of #450. Separate pages cover [wheel and Jupyter installation](../system-installation/python-jupyter.md), [building the library](../system-installation/python-build.md), and [notebook acceptance](notebook-acceptance.md). [C2/C3 history](embedded-integration-history.md) does not replace this contract.

## Roles and scope

| Interface | Purpose | Requires a running server |
| --- | --- | --- |
| `retractordb.Engine` | Compiles RQL and executes a plan inside Python | No |
| `retractordb.Storage`, `load_descriptor` | Reads existing storage offline | No; an active server can exclude access |
| `retractordb.client.Client` | Observes a running instance through `xqry` | Yes |

`Engine` executes on a logical timeline, without a wall clock, IPC thread or terminal. It does not join the bus, claim a namespace or publish streams to `xqry`. Use `xretractor` for real-time processing and the [monitoring API](stream-monitoring-api.md) to read its service streams. The embedded library provides no real-time guarantees.

The package imports `_core` lazily when the embedded API is requested. The pure client works without the extension. NumPy is the embedded library's dependency; only an explicitly imported `retractordb.torch` imports PyTorch. Installing the client with `pip install ./api/python` replaces the wheel distribution of the same name, including `_core`; use separate environments.

## Complete example

The example puts input outside the engine-owned directory, executes a plan, verifies values and checks DLPack sharing. The PyTorch part is optional.

```python
from pathlib import Path
from tempfile import TemporaryDirectory
import numpy as np
import retractordb as rdb

with TemporaryDirectory() as directory:
    source = Path(directory) / "input.txt"
    source.write_text("\n".join(str(value) for value in range(10, 81, 10)) + "\n")
    with rdb.Engine() as engine:
        engine.compile(f"""
            DECLARE a INTEGER STREAM src, 1/2 TEXTFILE '{source}'
            SELECT a*2 STREAM dst FROM src
        """)
        assert engine.run() == 8
        assert engine.slots_done == 8 and engine.time == 4
        assert [row[0] for row in engine.rows("dst")] == list(range(20, 161, 20))
        descriptor = engine.schema("dst")
        field = descriptor[0].name
        block = engine.to_numpy("dst", fields=[field], dtype="float64")
        np.testing.assert_array_equal(block[:, 0], np.arange(20, 161, 20))
        window = engine.window("dst", fields=[field], size=4, stride=2)
        assert window.shape == (3, 4, 1)
        try:
            import torch
        except ImportError:
            torch = None
        if torch is not None:
            tensor = torch.from_dlpack(window)
            assert tensor.data_ptr() == window.to_numpy().__array_interface__["data"][0]
    np.testing.assert_array_equal(block[:, 0], np.arange(20, 161, 20))
    assert window.shape == (3, 4, 1)
```

Eight records produce eight slots and logical time 4 at interval 1/2. Records, arrays and windows copy engine results and remain readable after the engine closes.

## Engine lifecycle and execution

| API | Contract |
| --- | --- |
| `Engine(storage_dir="", lock_dir="", config="")` | A separate instance and Memory Store; a private temporary directory by default |
| `compile(rql, until_eof=True)` | Closes the previous plan, then parses, compiles and constructs a new model |
| `step()` | Returns the executed slot index starting at 0, or `None` after end of input |
| `run(slots=None)` | Returns slots executed by this call; without a budget, runs until EOF |
| `has_plan`, `failed`, `end_of_input` | Plan presence, a latched slot failure and end of input |
| `slots_done`, `time` | Total executed slots and exact logical time as `Fraction` |
| `storage_dir` | Effective plan directory, or the default directory without a plan |
| `streams()`, `schema(stream)`, `is_declared(stream)` | Stream names, descriptor and declared-source status |
| `record_count(stream)`, `retained_from(stream)` | Total record counter and oldest readable index |
| `record(stream, index)` | One copied record; negative indices count from the end |
| `rows(stream, first=None, count=None)` | Iterator of copied records, starting at the oldest retained record by default |
| `close()`, `with Engine() as engine` | Closes the plan and releases resources; ordinary close is idempotent |

The default `until_eof=True` stops after the slot in which the first declared source runs dry. `until_eof=False` allows sources to wrap at EOF. A plan without an ending input needs a budget such as `run(slots=8)` or interruption. A slot is not a record count for every stream: streams can have different intervals and delayed starts.

A failed recompilation also closes the previous plan; refusal does not restore it. After K2/K3, fix the request and compile again. Failure inside a slot latches `failed`; subsequent `step()` repeats the failure class until recompilation. Existing results can remain readable after K4. K1 additionally taints the module until interpreter restart.

Compilation, stepping, running and record reads release the GIL. `run()` checks Python signals approximately every 50 ms between slots, allowing `KeyboardInterrupt`; this is not a maximum interruption delay for a long slot. Diagnostics reach `logging.getLogger("retractordb")`.

## Storage directory and offline access

`Engine()` creates a private directory that survives `close()` and is removed on destruction. An explicit `storage_dir`, or an overriding RQL `STORAGE`, must name an empty directory on first use or one with a valid `.retractordb-embedded` ownership marker. Foreign directories are refused. The marker does not establish that an owner process is still alive.

The directory lock lasts until the plan's storages close. It excludes another `Engine` and `Storage` in a marked directory, including through path aliases or another process. Process death releases the lock. Explicit directories remain on disk; recompilation can replace their descriptors and results. Preflight refusal preserves old artifacts but closes the plan; later I/O failures are not transactional.

Inputs must be outside the result directory and outputs inside it. A missing declared source is refused during `compile()` as `IOError` with `errno=ENOENT` and the path in the message. The service still produces NULL records for this case. Removal after compilation is a separate case. Explicit `DISPOSABLE` still authorizes removal of its source after use.

Opening `Storage` can rebuild `.meta`, so access is offline. For a directory used by a service, pass its `lock_dir` or `config` naming a TOML file with `paths.lock_dir`; the argument wins. Configuration is read only when explicitly named. Without either, the check guesses TMPDIR and reports a `UserWarning` and an INFO record to the `retractordb` logger.

`[embedded] lenient_lock_dirs` lists directories where only a held lock refuses access. Without the key, the system temporary directory is the default lenient directory. The key replaces that list; other directories are checked strictly. The opening check does not exclude a later daemon start or a service using another lock directory. A private `Engine()` directory skips the service-lock check.

## Storage, Descriptor and Record

| API | Contract |
| --- | --- |
| `load_descriptor(path)` | Reads `.desc`; missing files raise `NoSuchStream`, invalid descriptors `CorruptDescriptor` |
| `Descriptor` | A sequence of `Field`; `size_bytes` excludes configuration fields, `flat_element_count` counts data elements |
| `Field` | `name`, `length`, `array_count`, `type` (`FieldType`) properties |
| Descriptor methods | `has_field`, `field_index`, `byte_offset`, `field_type_name`, `storage_policy` |
| `Storage(qry_id, file_name, storage_param="", storage_type="DEFAULT", lock_dir="", config="")` | Opens existing storage offline without compiling a plan |
| `Storage.descriptor`, `record_count`, `is_declared`, `closed` | Schema, record counter, source kind and handle status |
| `Storage.read(i)`, `storage[i]`, `len(storage)` | Copied record or record count; negative indices count from the end |
| `Storage.close()` and context manager | Closes storage, index and directory lock; reads after close refuse |
| `Record.index`, `descriptor`, `record[i]` | Index, schema and flat elements of an owned payload copy |

Values become `int`, `float`, `str`, `Fraction` for RATIONAL, tuples for pairs and `None` for NULL. `STRING[N]` occupies one value slot, while a numeric array occupies N. Configuration fields occupy no record slot. Direct `Storage` cannot read BINFILE, TEXTFILE or DEVICE sources; a plan's source results are readable through `Engine` within retained history.

Retention can expire indices. `record_count` is a logical counter, not the count of all still-readable records; use `retained_from`. Default `rows()` and `to_numpy()` read the retained tail. An expired index refuses instead of returning another ring-buffer entry.

## Errors

```text
RetractorDBError
+-- ConfigError (also ValueError)
|   +-- PlanError
|       +-- RQLSyntaxError
|       +-- CompileError
|       +-- CorruptDescriptor
+-- IOError (also OSError)
+-- InternalError
+-- NoSuchStream
+-- StorageError
```

| Class | Python result | State afterwards |
| --- | --- | --- |
| K1, broken invariant | `InternalError` | Module tainted; guarded entries refuse until interpreter restart; `close()` remains available |
| K2, plan refusal | `PlanError`: syntax, compilation, corrupt descriptor | Correct the input and retry; failed `compile()` leaves no old plan |
| K3, request refusal | `ConfigError`, also `ValueError` | Instance remains usable |
| K4, environment failure | `IOError`, also `OSError` | A slot failure stops the plan until recompilation; compile refusal creates no plan |
| K5, invalid data value | `None` or `NaN` | Execution continues; engine warning exists outside Release builds |
| K6, deprecated syntax | `DeprecationWarning` from `compile()` | Plan remains usable |
| K7, abort or failure outside the handled boundary | Process termination | Restart the kernel |

`IOError.errno` preserves a system code or uses EIO when no code is available; `filename` is set when the call accepts a path argument. Otherwise the path can be in the message. Field/stream names, indices, array conversion and signatures can raise standard `KeyError`, `IndexError`, `ValueError` or `TypeError`; not every exception derives from `RetractorDBError`.

Handled entries turn K1/K4 into exceptions but do not guarantee survival of every core failure. `FatalError` or `EnvironmentError` inside `noexcept`, destruction or stack unwinding can terminate the interpreter, including at the `Engine.close()` and destructor boundary. Do not catch `InternalError` intending to continue computation in the same kernel.

## Memory ownership, NumPy and DLPack

| Operation | Shape and ownership |
| --- | --- |
| `to_numpy(stream, fields=None, dtype="float64", first=None, count=None)` | `(records, values)`; new array copying engine results |
| `window(stream, fields=..., size=..., stride=1, dtype="float32")` | `(window_count, size, values)`; contiguous array owned by `Window` |
| `Window.to_numpy()`, `np.asarray(window)` | Shares the window array without another copy for the same dtype |
| `torch.from_dlpack(window)` | Shares that CPU array, never engine memory |

`fields` determines value-axis order; numeric arrays are flattened. STRING, INTPAIR and IDXPAIR have no dense numeric form. Export dtypes are `float32`, `float64`, `int32`, `int64`. Floating exports map NULL to NaN; integer exports reject NULL, infinity and out-of-range results with `ValueError`. Finite fractions truncate toward zero. Projection passes through double, so use `Record`, rather than a dense array, for full precision of large integers.

`size` and `stride` must be positive. Fewer than `size` records produce `(0, size, values)`. For N retained records with N >= size, window count is `1 + (N-size)//stride`. `sliding_window_view` selects the windows, which are then copied into a contiguous array. Arrays and tensors survive later slots, engine close and destruction. Mutating the window array is visible to its shared tensor but does not modify engine results.

## Devices, PyTorch and threads

`retractordb.torch.as_tensor(window, device="cpu")` shares CPU memory; an explicitly requested other device transfers and copies. `StreamDataset(engine, stream, fields=..., window=..., stride=1, dtype=torch.float32, device="cpu")` yields `(size, values)` items. Each iteration reads current results, so new slots can add windows to a later epoch.

Use `DataLoader(..., num_workers=0)`. A worker refuses before accessing the engine; neither `fork` nor creating Engine in a worker initializer belongs to this dataset contract. Serialize all calls on one instance, including reads, getters, `compile()` and `close()` during `run()`. The GIL does not protect engine state; concurrent compilation or execution of separate engines has no general thread-safety guarantee.

CPU/DLPack does not pin engine buffers or provide pinned host memory for CUDA. CUDA transfer is a separate operation. MPS rejects float64 before transfer; choose float32. The CPU guard test is not MPS hardware acceptance. The #448 Colab T4 demonstration uses CUDA, fp16 and GradScaler; it does not establish all-device support. DeviceWindowLoader, MPS acceptance and PyPI publication remain optional follow-up tasks outside the epic.

## Embedded-plan limits

`compile()` refuses DUMP, SYSTEM, `:ROTATION` and DEVICE sources as `CompileError`: they require service state or execution phases that Engine lacks. A missing input gives the `IOError` described above. Python push ingest and mobile targets are unavailable. The complete service and its configuration remain the responsibility of `xretractor`.

## Contract sources and tests

| Area | Code-repository sources | Tests in `api/python/tests` |
| --- | --- | --- |
| Plan, EOF, recompilation and directory | `src/embed/engine.cc`, `storageGuard.cc`, `src/python/module.cpp` | `test_engine.py`, C++ `ut_embedEngine` |
| Descriptors and offline reads | `src/python/module.cpp`, `src/rdb/lib/descriptor.cc` | `test_descriptor.py`, `test_storage.py` |
| K1-K7 and reuse | `src/include/fatalError.hpp`, `src/python/module.cpp` | `test_error_classes.py`, `test_fatal_paths.py`, `test_reentry.py` |
| Copies, windows and devices | `retractordb/engine.py`, `retractordb/torch.py`, `src/python/module.cpp` | `test_window.py` |
| Isolation and logical equivalence | `src/embed/engine.cc`, `src/retractor/lib/dataModel.cpp` | `test_isolation.py`, `test_reference.py` |

`retractordb/*.py` paths are relative to `api/python/`. Test names identify coverage, not execution on every platform. `test_reference.py` compares the common scope with `xretractor -u`, including schema, NULL, metadata and logical scheduling; it does not measure real time. Missing sources and service-only features are excluded. Record the conditions and results of each acceptance run separately.
