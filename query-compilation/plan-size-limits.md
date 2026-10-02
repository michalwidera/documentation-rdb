# Plan Size Limits

RetractorDB rejects a plan whose dimensions exceed the safe range of the parser, descriptor, or history memory. These checks run at ordinary startup, in `xretractor -c`, for ad-hoc queries, and during `xqry --reset`. In the last case, rejection of the new plan leaves the running plan unchanged. `src/include/rdb/sizeLimits.hpp` is the shared source of numeric limits for the RQL and DESC parsers and the compiler.

## Layer 1: individual literals

| Dimension | Allowed value | Applies to |
| --- | ---: | --- |
| Field length | `1..65536` | `TYPE[N]`, `STRING[N]`, and `to_string(x : N)`; the DESC parser uses the same field limit. |
| History reach | up to `65536` | The step and absolute window width of `@(step, window)`, record-window width, `>N` shift, and `DUMP -L TO R` bounds. Steps and widths must be positive; shifts and `DUMP` bounds may be zero. |
| `DUMP ... RETENTION` | `0..256` | Number of concurrently retained dump tasks; `0` means no task retention. |
| Generator size | `1..148` | `STREAM name[N]`; after generator expansion, the whole plan may have at most 148 streams. |

A storage `RETENTION` capacity must be positive. In its two-part form, the segment count may be `0`, meaning no limit on disk segments. A literal outside its numeric type is a parser error; exceeding one of the bounds above produces a message such as `AGSE step 65537 exceeds the limit 65536`. `to_string(x : 0)` produces `to_string width 0 must be greater than zero`; it does not create a zero-width field.

## Layer 2: dimensions after plan expansion

| Compiler check | Limit | Why it is separate |
| --- | ---: | --- |
| Each output field, including derived fields | `65536` elements or string bytes | Concatenation can exceed the limit even if every literal was valid. |
| Output record of each stream | `1 MiB` (`1048576` bytes) | Sum of field sizes after schema inference. |
| Input record of each stream | `1 MiB` (`1048576` bytes) | An AGSE window, sum, or interleave can build an input larger than the output record. |
| Sum of flat record elements across the plan | `2^18` (`262144`) | Bounds descriptor construction and execution cost, including many small fields. |
| Logical origin and startup tail | `INT_MAX` (`2147483647`) slots each | Compiler results must fit the `int` representation used in the plan. |

The 148-stream check after expansion applies to plans with a generator and runs before copying its instances. A plan without a generator may pass that stage, but the bus slot limit is checked when the plan is registered or replaced. Record and field sizes are checked before building potentially large descriptors.

The compiler names the stream and the exceeded dimension, for example `Stream 'x' reads an input record of 1048577 bytes; the limit is 1048576`, `Plan needs 262145 record elements; the limit is 262144 (reached at stream 'x')`, `Stream 'x' has a logical origin of ... slots; the limit is 2147483647`, or the corresponding `startup latency` message.

## RAM history budget

`[limits] history_memory_mib` in `retractor.toml` sets the plan's combined history budget, defaulting to `1024` MiB. For each `DECLARE` source and each `MEMORY` store, the compiler sums the number of retained records multiplied by record size plus `rdb::payload` overhead. A source's capacity follows consumer needs; a `MEMORY` ring uses the greater of `RETENTION n` and the plan's need. File-store history does not count toward this budget.

Exceeding the budget fails compilation with `Plan keeps ... bytes of stream history in memory; the budget [limits] history_memory_mib = ... allows ...`, which also identifies the stream with the largest share. The setting must be positive; `0` or a negative number logs a warning and restores the `1024` MiB default. This budget is not a process-wide memory limit or an IPC queue limit. See [xretractor configuration](../appendices/command-line-options/xretractor.md#configuration-file-toml) and [Storage Types](../query-language-construction/select-command/storage-types.md).
