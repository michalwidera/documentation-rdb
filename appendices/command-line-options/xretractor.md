# xretractor

The `xretractor` program is RetractorDB's core process. It compiles files containing RQL queries and executes the data-processing plan. It's built to run autonomously as a systemd daemon process.

## Modes of operation

`xretractor` starts in one of two modes:

| Mode                     | Description                                                                  |
| ------------------------ | --------------------------------------------------------------------- |
| **Processing**        | Default - compiles queries and starts the query-execution loop   |
| **Compile only** `-c` | Compiles queries without starting the loop; allows visualizing the plan |

Calling `-h` shows a different option list depending on the mode - option shorthands overlap, so pay attention to which mode a given option applies in.

---

## Processing mode (default)

```
$ xretractor -h
xretractor - compiler & data processing tool.

Usage: xretractor queryfile [option]

Available options:
  -h [ --help ]               Show program options
  -b [ --build-info ]         show optimizer build configuration
  -c [ --onlycompile ]        compile only mode
  -q [ --queryfile ] arg      query set file
  -r [ --quiet ]              no output on screen, skip presenter
  -s [ --status ]             check service status
  --cleanup                   remove leftovers of dead instances and exit
  -v [ --verbose ]            verbose mode (show stream params)
  -x [ --xqrywait ]           wait with processing for first query
  -n [ --name ] arg           instance name; own IPC area and lock
  -a [ --autoname ]           generate a docker-style instance name
  -k [ --noanykey ]           do not wait for any key to terminate
  -j [ --service ]            service mode: log to stderr (journald)
  -t [ --realtime ]           enable real-time scheduling
  -f [ --no-clock ]           offline mode: compute slots without waiting
  -u [ --until-eof ]          forces one-shot all sources
  -g [ --config ] arg         config file (TOML); overrides search
  -m [ --llimitqry ] arg (=0) loop iteration limit, 0 - no limit
```

### Processing-mode options

| Option | Meaning |
| ----- | --------- |
| `help` | Displays the help text. The list differs depending on the mode (with or without `-c`). |
| `build-info` | Prints the optimizer configuration the binary was built with (the `RDB_OPT_*` flags and `RDB_BENCH_PROBE`) and exits without starting the engine. It is handled before the configuration file is loaded and validated, so it also works on a host with an invalid `storage.dir`. The output is stable and meant for automated processing - both `scripts/buildrdb.sh` and the `it_optimizer_ablation-build-info` test rely on it. See the appendix on production builds and diagnostic variants for details. |
| `onlycompile` | Switches the tool into "compile only" mode. The query-execution loop is not started. |
| `queryfile` | The name of the query file to compile and run. |
| `quiet` | Skips displaying results on screen. Processing runs normally, but the result presenter isn't started. |
| `status` | Checks the instance lock selected by `--name`, `RDB_NAMESPACE`, or the historical empty name. `Running` means another process holds the same identity. |
| `cleanup` | Removes recognized leftovers of dead instances and exits without starting a plan. Live owners remain protected; scope and limitations are described below. |
| `verbose` | An increased-verbosity mode - shows stream parameters. A leftover from the development phase; likely to be kept. |
| `xqrywait` | Compiles the queries and holds off the processing loop until the first query arrives from an `xqry` process. Required when using `-m N` at the same time in scripts and tests: without this flag, the server may process all N cycles before the client manages to connect, resulting in no data and `xqry` waiting until it times out. The first command received from `xqry` (e.g. `-d` or `-s`) unblocks the processing loop. |
| `name arg` | Gives the instance a stable name. The name selects a separate lock file and IPC area and lets commands be routed through `xqry --server`. It may contain at most 32 lowercase letters, digits, `_`, and `-`, and its first character must be a letter. |
| `autoname` | Generates a container-style instance name and prints it at startup. Mutually exclusive with `--name`. |
| `noanykey` | No keypress interrupts the processing loop. Without this option, pressing any key stops the system. |
| `service` | Service mode: the log goes to `stderr` (captured by journald), with no log file in the temporary directory, no timestamp of its own, and no ANSI codes. The mode can also be enabled through the `XRETRACTOR_SERVICE` environment variable set to any value other than empty or `0` - convenient in a systemd unit via `Environment=`. |
| `realtime` | Enables real-time scheduling: `SCHED_FIFO`, `mlockall`, and absolute sleep for the processing thread. Requires `CAP_SYS_NICE` and `CAP_IPC_LOCK` capabilities (or root). Recommended in production environments requiring deterministic response time. |
| `no-clock` | Offline mode: retains the rational timeline, logical indices, origins, and plan tails, but skips wall-clock waiting. It cannot be combined with `--realtime`. |
| `until-eof` | Makes declared file sources non-wrapping and stops when the first one runs out of data. A `DEVICE` source has no end of file. |
| `config` | Path to a configuration file in TOML format. It overrides the standard search order (`/etc/retractor/retractor.toml`, then `$XDG_CONFIG_HOME/retractor/retractor.toml` or `~/.config/retractor/retractor.toml`). A missing configuration file is a valid state - the program starts with built-in defaults. |
| `llimitqry` | Limits the number of iterations in the query-execution loop. A value of `0` means no limit. |

### Multiple instances

Several named instances can run concurrently:

```bash
xretractor measurements.rql --name measurements --noanykey &
xretractor diagnostics.rql --name diagnostics --noanykey &
xqry --bus
```

Each receives its own lock and IPC objects. The shared bus nevertheless rejects a plan that collides with a live instance by stream name, written storage file, or `:ROTATION` counter file. The check happens before artifacts are removed. Omitting `--name` preserves the historical unnamed instance.

Service mode provides a separate guarantee: exactly one service instance may run in each `RDB_NAMESPACE`; in the default namespace it is named `service`. See [Multiple Instances and the Bus](../../data-processing-system-architecture/multiple-instances-and-bus.md).

### Cleaning up leftovers

```bash
xretractor --cleanup
```

The command does not start a plan. It attempts to acquire locks on recognized resources and removes only those without a live owner holding the lock. The same mechanism runs when an instance exits.

| Scope | Action |
| --- | --- |
| Instance lock files | Scans `paths.lock_dir` selected by configuration, defaulting to the process's temporary directory. |
| IPC identities | Scans the shared `/tmp`; removes an abandoned lock and its command queue, response segment, and map mutex. |
| Bus | Removes unused segments of the current `xrdbbus_v6` layout protected by presence locks. |

The scope is not restricted to an instance selected with `--name` or a single `RDB_NAMESPACE`. Filesystem permissions still control access to resources. The command does not enumerate or remove client response queues; it also leaves v5 and older segments untouched because they do not participate in the presence-lock protocol.

The output counts removed instance locks, IPC identity sets, and segments, for example:

```text
Removed leftovers of dead instances: 1 instance lock(s), 1 IPC identity set(s), 1 bus segment(s).
```

The IPC-set count is not a count of individual queues. Completion does not establish that resources outside the command's scope were removed. For a custom lock directory, select the appropriate TOML using `--config`.

### Clock-free batch processing

The simplest run over a complete input file without manually selecting an iteration count is:

```bash
xretractor query.rql --no-clock --until-eof --noanykey --quiet
```

`--no-clock` removes sleeps only. It does not change slot order or artifact content, making it suitable for fast verification after completion. It can outrun an `xqry` client, however, so it is not intended for live observation.

`--until-eof` prevents a sequential source from returning to the start of its file. EOF is checked after a slot has been processed, exactly before the first record that would otherwise have to use synthetic NULL beyond the input. With several sources, the first exhausted one stops the run so the plan does not continue with a missing input. It may be combined with `-m N`; whichever condition occurs first wins.

> **⚠️ Warning** Short options depend on the mode. During execution, `-f` means `--no-clock` and `-u` means `--until-eof`. With `-c`, the same letters mean `--fields` and `--rules`, respectively, and do not start processing.

> **_NOTE:_** `noclock_offline` verifies equivalence between paced and offline execution; `untileof_stop` verifies first-EOF termination and the non-wrapping control.

---

## Compile-only mode (`-c`)

```
$ xretractor -h -c
xretractor - compiler & data processing tool.

Usage: xretractor -c queryfile [option]

Available options:
  -h [ --help ]          show help options
  -b [ --build-info ]    show optimizer build configuration
  -c [ --onlycompile ]   compile only mode
  -q [ --queryfile ] arg query set file
  -r [ --quiet ]         no output on screen, skip presenter
  -d [ --dot ]           create dot output
  -m [ --csv ]           create csv output
  -f [ --fields ]        show fields in dot file
  -t [ --tags ]          show tags in dot file
  -s [ --streamprogs ]   show stream programs in dot file
  -u [ --rules ]         show rules in dot file
  -i [ --hideruleprog ]  hide rule program in rules (-u) output
  -p [ --transparent ]   make dot background transparent
  -w [ --diagram ] arg   create diagram output
  -z [ --shmbudget ]     show shared memory budget of the compiled plan
```

In this mode, options for creating diagrams and diagnostic dumps, described in more detail elsewhere in this work, are available.

### Visualization and diagnostic options

| Option | Meaning    |
| ----- | ------------ |
| `help` | Displays the help text (identical to processing mode; the list differs depending on the mode). |
| `build-info` | Identical in meaning to processing mode - prints the optimizer configuration and exits. The `-c` flag does not affect the output; the option is available in both modes so that the configuration dump can be obtained regardless of how the program is invoked. |
| `onlycompile` | On - this table describes the options that apply while the `-c` flag is active. |
| `queryfile` | The name of the query file to compile. |
| `quiet` | Tests only the compilation process itself, without presenting results. The other presentation options are not started. Included for development purposes. |
| `dot` | Creates a text file in DOT format describing the hierarchical structures produced by the compiler. The file can be passed to the Graphviz tool to generate a graphical description of the dependencies. |
| `csv` | Exports the hierarchical data structures to a CSV file (comma-separated values). |
| `fields` | Adds, to the DOT graph, the fields and their types for each data stream. |
| `tags` | Adds, to the DOT graph, the internal-language programs that build the fields of each query. Must be called together with `fields` - it visually links the fields to their programs. |
| `streamprogs` | Adds, to the DOT graph, the stream-algebra programs that build each query's streams. |
| `rules` | Adds alerting rules to the graph. |
| `hideruleprog` | Hides the programs describing the alerting conditions (used together with `rules`). |
| `transparent` | Generates the graph with a transparent background. |
| `diagram` | Generates marble diagrams. The argument takes the form `type:cycle_count`: `type` (`0` or `1`) determines whether the diagrams show timestamps; `cycle_count` sets the number of cycles shown in the diagram. |
| `shmbudget` | Reports the fixed IPC reservation, capacity, and free space of the `shm_open` filesystem (usually `/dev/shm`), plus the cost of one client queue for each plan interval. This lets an operator estimate the number of concurrent subscriptions before starting a server. |

---

## Configuration file (TOML)

The `--config` option points at a configuration file; without it the program searches two locations in layered fashion, in the order given, each later layer overriding keys from the previous one:

1. `/etc/retractor/retractor.toml` - system layer,
2. `$XDG_CONFIG_HOME/retractor/retractor.toml` (or `~/.config/retractor/retractor.toml`) - user layer.

The absence of any file is a **valid state** - the program starts with default values. A TOML syntax error in a searched layer produces a warning and skips that layer; with an explicitly given path (`--config`), a missing file or a syntax error is hard, because it is an explicit user request. The same file is also read by `xqry` (under the `-e` short option), so the `[ipc]` and `[timing]` sections apply to both processes.

| Key | Default | Meaning |
| --- | ------- | ------- |
| `storage.dir` | _(none)_ | Default artifact directory. Applied **only** when the RQL set contains no `:STORAGE` directive - RQL wins. The directory must exist and be writable, otherwise the program exits with `Configuration error: storage.dir …`. |
| `ipc.queue_buffer_seconds` | `10` | IPC queue depth expressed in seconds of stream; the element count is `seconds / interval`. |
| `ipc.min_queue_elements` | `100` | Lower bound on queue capacity, independent of the stream interval. |
| `ipc.client_response_max_fails` | `300` | Multiplier for the `xqry` response time budget. A monotonic-clock deadline is set to this value times the polling interval (10 ms) and covers both waiting for space in the command queue and waiting for the response. |
| `timing.server_startup_wait_s` | `30` | Maximum time `xqry --wait-server` waits for server readiness. |
| `timing.server_startup_poll_ms` | `100` | Polling interval while waiting for the server to start. |
| `timing.query_no_data_timeout_ms` | `10000` | No-data timeout after which the `xqry` client considers the server dead. |
| `scheduling.rt_priority` | `50` | `SCHED_FIFO` priority in `--realtime` mode; allowed range 1–99. |
| `paths.lock_dir` | _(system temp directory)_ | Directory for instance lock files. For systemd services, `/var/run/retractor` or `$XDG_RUNTIME_DIR` is recommended. The path must be absolute. It does not change the fixed `/tmp` directory for IPC identity locks. |
| `server.autoname` | `false` | Generates a name when neither `--name` nor `--autoname` was given. An explicit `--name` wins. `false` preserves the historical unnamed instance. |
| `service.query_file` | _(value from the build configuration)_ | The query file overwritten when a set is handed to a running service. Used only as a fallback, when the service did not report its own `QUERYFILE` in the lock file. It must match the `ExecStart` argument of the systemd unit - configuration does not change `ExecStart`. |
| `service.unrestricted` | `false` | Allows a `DO SYSTEM` rule in a plan accepted over the `xqry --reset` channel. The default value refuses such a plan as a whole (→ [xqry](xqry.md#the-do-system-rule-does-not-pass-through-this-channel)). With `true` the instance leaves a warning in the log at every start, and anyone able to open its IPC objects runs shell commands under its account. The key is read at process start-up, so it is set by the same authority that writes the service's plan file; it never opens the ad-hoc channel. |

Every IPC object the server creates - the response-map segment, the map mutex, the command queue, the response queues, and the bus segment - is given an explicit `0600` mode, so the trust boundary is the account the instance runs under, not the umask of the systemd unit. The client loses nothing by it: `xqry` opens all of these objects through `open_only` only, so it has to run under that account anyway.

Out-of-range values do not stop the service: the program logs a warning and uses the default. The exception is `storage.dir`, whose invalidity is a hard error - it would mean results landing somewhere unintended, or nowhere.

Example file:

```toml
[storage]
dir = "/var/lib/retractor"

[ipc]
queue_buffer_seconds = 30

[scheduling]
rt_priority = 60

[paths]
lock_dir = "/var/run/retractor"

[server]
autoname = false
```

> **_NOTE:_** Layer loading and validation are covered by the `ut_appConfig` unit test; hard rejection of an invalid `storage.dir` by the `config_storage_validation` integration test.

---

## Service and plan replacement

Starting without an `.rql` file, or with an empty one, creates an idle instance with working IPC. The first or a later complete plan can be loaded without restarting:

```bash
xqry --server service --reset plan.rql
```

The server parses and compiles the complete contents, checks resource collisions, reserves the new set, and then switches plans at a slot boundary. Rejection leaves the old plan unchanged. An empty reset file returns the server to idle. On a service instance, accepted contents are also written to the service's startup file.

The alternative `xretractor new-plan.rql` path detects a running systemd unit, validates the set, atomically overwrites its startup file, and requests a restart. Explicitly selecting another identity with `--name` or `--autoname` starts a separate instance instead. After a critical error, the service plan is cleared so systemd restarts the process safely in idle state.

---

## Version Information

At the end of every help message, a line with build information is displayed:

```
Branch: issue_31-doc:2707ce0,
Code compiler: GNU Ver. 13.3.0,
Build time: 2512211449,
Type: Debug
```

| Field             | Meaning                                                                              |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `Branch`         | The repository branch name and the commit hash the program was built from          |
| `Code compiler`  | The GCC compiler version used for the build                                               |
| `Build time`     | The compilation date and time, in `YYMMDDHHMM` format (here: December 21, 2025, 14:49)  |
| `Type`           | The build type: `Debug` or `Release`                                                      |

The next line indicates the log file location:

```
Log: /tmp/xretractor.log
```

The file `/tmp/xretractor.log` records the history of invocations and the system's internal events. In a production environment, this file should be cleaned up or rotated regularly.

The last line contains MIT license information, which allows safe use of the code in corporate applications.
