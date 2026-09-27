# STORAGE Types

The `STORAGE` clause in the `SELECT` command, and the `SUBSTRAT` directive, accept one of the following identifiers. Each maps to a specific data-accessor class in the implementation.

## Type table

| Keyword         | C++ class                              | Retention | Shadow | Purpose                                          |
| ---------------- | -------------------------------------------------- | :------: | :----: | ------------------------------- |
| `DEFAULT`      | `groupFile<posixBinaryFileWithShadow>`| yes      | yes    | Default production mode; a `.shadow` file protects modifications |
| `DIRECT`       | `groupFile<posixBinaryFile>`          | yes      | no     | Retention without shadow protection             |
| `MEMORY`       | `memoryFile`                          | yes (RAM)| no     | Data in memory only; circular buffer, never written to disk |
| `POSIX`        | `posixBinaryFile`                     | no       | no     | A single binary file; no retention              |
| `POSIXSHD`     | `posixBinaryFileWithShadow`           | no       | yes    | A single file with shadow protection; no retention |
| `GENERIC`      | `genericBinaryFile`                   | no       | no     | Generic binary file                             |
| `DEVICE`       | `binaryDeviceRO`                      | no       | no     | Binary device; read-only; looping depends on `ONESHOT` |
| `TEXTSOURCE`   | `textSourceRO`                        | no       | no     | Text file; read-only; looping depends on `ONESHOT` |

**Retention** - artifacts are rotated, older files are deleted automatically (requires `RETENTION capacity segments` on `SELECT`).\
**Shadow** - every modification is written to a separate `.shadow` file; historical data is protected from being overwritten.

For `MEMORY`, retention works in memory as a circular buffer: successive appends overwrite the oldest slot (`index % capacity`). Data is not segmented into files and never reaches disk. `RETENTION n` sets the ring size (at least what the plan needs) - the same for `STORAGE MEMORY` and `VOLATILE`; the segmented form `RETENTION n s` is a compilation error here.

Even without `RETENTION`, a `MEMORY` store has a finite capacity: at least one record, increased by the compiler to meet consumer needs. Formerly, `STORAGE MEMORY` could grow without bound or, with `RETENTION n`, write to disk under the wrong storage type. The ring size and total history cost now count against the [plan budget](../../query-compilation/plan-size-limits.md#ram-history-budget). An ad-hoc `DO DUMP` rule that reaches deeper than the existing ring is rejected; attaching a rule does not enlarge a live store.

### Retention on disk

The `DEFAULT` and `DIRECT` stores keep data in segments: `RETENTION capacity segments` keeps at most `segments` files of `capacity` records each, and the oldest segment is deleted when a new one is opened. The one-argument form `RETENTION n` means only the size of a `MEMORY` ring; on a file store it is a compilation error with the hint `RETENTION n <segments>`. `segments = 0` means "no segment limit".

For example, `RETENTION 100 STORAGE DIRECT` is rejected because it omits the segment count. Write `RETENTION 100 4 STORAGE DIRECT` instead. For `STORAGE MEMORY` the rule is reversed: `RETENTION 100` sizes the ring, while `RETENTION 100 4` is rejected as segmented retention on a RAM store.

Right after a rotation only `(segments - 1) * capacity + 1` records remain on disk. A plan that reads further back into the stream (a `>N` shift, an `@` window, a `DUMP` range) is a compilation error - reading a deleted segment would stop the running server.

A file stream without `RETENTION`, with `segments = 0`, or in a store without retention (`POSIX`, `POSIXSHD`, `GENERIC`) grows on disk without bound. This is allowed - durable history - but explicit: at startup and in `-c` mode `xretractor` lists such streams on stderr, including intermediate streams extracted by the compiler. The operator can bound every `DEFAULT`/`DIRECT` stream without `RETENTION` with the key `default_retention = [capacity, segments]` in the `[storage]` section of `retractor.toml`; without that key the engine deletes no data.

A start without the `ROTATION` directive begins `SELECT` outputs and substrates from scratch: it deletes their whole file families - data with its `.shadow` file, `.desc`, `.meta`, and retention segments. It does not delete `DECLARE` source files. With `ROTATION`, retained disk-store files must match the plan: if a kept `.desc` has another storage type or retention, the start (and `xqry --reset`) is refused, naming the stream and both configurations. For `MEMORY`, old descriptor and metadata files are removed even under `ROTATION`, so the new ring cannot inherit the previous plan's configuration. Changing the capacity over kept segments would shift record addressing, so the operator chooses: restore the previous configuration in the plan, or remove the stream's files.

> **_NOTE:_** The `MEMORY` type (SUBSTRAT 'memory') is covered by the tests: `issue61_tmpmem` (serial and parallel), described in the appendix [Integration Tests](../../appendices/integration-tests.md).

## When to use which

The choice depends on the environment's requirements:

* **Production environment, critical data** → `DEFAULT` (retention + shadow)
* **Production environment, historically insignificant data** → `MEMORY` (zero disk usage, retention in RAM)
* **Development and debugging** → `DEFAULT` or `DIRECT` (data visible on disk)
* **Reading from a device or a text file** → `DEVICE` / `TEXTSOURCE` (respectively)

## Example

```rql
SELECT str1[0] STREAM str1 FROM core0 STORAGE MEMORY
SELECT str2[0] STREAM str2 FROM core0 RETENTION 100 4 STORAGE DIRECT
```

For substrates globally - the `SUBSTRAT` directive:

```rql
SUBSTRAT 'memory'
```
