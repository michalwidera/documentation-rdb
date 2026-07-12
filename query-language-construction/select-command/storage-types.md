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

**Retention** — artifacts are rotated, older files are deleted automatically (requires `RETENTION` on `SELECT`).\
**Shadow** — every modification is written to a separate `.shadow` file; historical data is protected from being overwritten.

For `MEMORY`, retention works in memory as a circular buffer: successive appends overwrite the oldest slot (`index % capacity`). Data is not segmented into files and never reaches disk.

> **_NOTE:_** The `MEMORY` type (SUBSTRAT 'memory') is covered by the tests: `issue61_tmpmem` (serial and parallel), described in the appendix [Integration Tests](../../appendices/integration-tests.md).

## When to use which

The choice depends on the environment's requirements:

* **Production environment, critical data** → `DEFAULT` (retention + shadow)
* **Production environment, historically insignificant data** → `MEMORY` (zero disk usage, retention in RAM)
* **Development and debugging** → `DEFAULT` or `DIRECT` (data visible on disk)
* **Reading from a device or a text file** → `DEVICE` / `TEXTSOURCE` (respectively)

## Example

```
SELECT str1[0] STREAM str1 FROM core0 STORAGE MEMORY
SELECT str2[0] STREAM str2 FROM core0 RETENTION 100 STORAGE DIRECT
```

For substrates globally — the `SUBSTRAT` directive:

```
SUBSTRAT 'memory'
```
