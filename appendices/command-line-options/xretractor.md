# xretractor

The `xretractor` program is RetractorDB's core process. It compiles files containing RQL queries and executes the data-processing plan. It's built to run autonomously as a systemd daemon process.

## Modes of operation

`xretractor` starts in one of two modes:

| Mode                     | Description                                                                  |
| ------------------------ | --------------------------------------------------------------------- |
| **Processing**        | Default — compiles queries and starts the query-execution loop   |
| **Compile only** `-c` | Compiles queries without starting the loop; allows visualizing the plan |

Calling `-h` shows a different option list depending on the mode — option shorthands overlap, so pay attention to which mode a given option applies in.

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
  -v [ --verbose ]            verbose mode (show stream params)
  -x [ --xqrywait ]           wait with processing for first query
  -k [ --noanykey ]           do not wait for any key to terminate
  -j [ --service ]            service mode: log to stderr (journald), no log
                              file
  -t [ --realtime ]           enable real-time scheduling (SCHED_FIFO,
                              mlockall, absolute wakeup)
  -g [ --config ] arg         config file (TOML); overrides search
  -m [ --llimitqry ] arg (=0) loop iteration limit, 0 - no limit
```

### Processing-mode options

| Option | Meaning |
| ----- | --------- |
| `help` | Displays the help text. The list differs depending on the mode (with or without `-c`). |
| `build-info` | Prints the optimizer configuration the binary was built with (the `RDB_OPT_*` flags and `RDB_BENCH_PROBE`) and exits without starting the engine. It is handled before the configuration file is loaded and validated, so it also works on a host with an invalid `storage.dir`. The output is stable and meant for automated processing — both `scripts/buildrdb.sh` and the `it_optimizer_ablation-build-info` test rely on it. See the appendix on production builds and research variants for details. |
| `onlycompile` | Switches the tool into "compile only" mode. The query-execution loop is not started. |
| `queryfile` | The name of the query file to compile and run. |
| `quiet` | Skips displaying results on screen. Processing runs normally, but the result presenter isn't started. |
| `status` | Checks whether another `xretractor` process is running, or has left behind lock files preventing multiple instances. |
| `verbose` | An increased-verbosity mode — shows stream parameters. A leftover from the development phase; likely to be kept. |
| `xqrywait` | Compiles the queries and holds off the processing loop until the first query arrives from an `xqry` process. Required when using `-m N` at the same time in scripts and tests: without this flag, the server may process all N cycles before the client manages to connect, resulting in no data and `xqry` waiting until it times out. The first command received from `xqry` (e.g. `-d` or `-s`) unblocks the processing loop. |
| `noanykey` | No keypress interrupts the processing loop. Without this option, pressing any key stops the system. |
| `service` | Service mode: the log goes to `stderr` (captured by journald), with no log file in the temporary directory, no timestamp of its own, and no ANSI codes. The mode can also be enabled through the `XRETRACTOR_SERVICE` environment variable set to any value other than empty or `0` — convenient in a systemd unit via `Environment=`. |
| `realtime` | Enables real-time scheduling: `SCHED_FIFO`, `mlockall`, and absolute sleep for the processing thread. Requires `CAP_SYS_NICE` and `CAP_IPC_LOCK` capabilities (or root). Recommended in production environments requiring deterministic response time. |
| `config` | Path to a configuration file in TOML format. It overrides the standard search order (`/etc/retractor/retractor.toml`, then `$XDG_CONFIG_HOME/retractor/retractor.toml` or `~/.config/retractor/retractor.toml`). A missing configuration file is a valid state — the program starts with built-in defaults. |
| `llimitqry` | Limits the number of iterations in the query-execution loop. A value of `0` means no limit. |

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
```

In this mode, options for creating diagrams and diagnostic dumps, described in more detail elsewhere in this work, are available.

### Visualization and diagnostic options

| Option | Meaning    |
| ----- | ------------ |
| `help` | Displays the help text (identical to processing mode; the list differs depending on the mode). |
| `build-info` | Identical in meaning to processing mode — prints the optimizer configuration and exits. The `-c` flag does not affect the output; the option is available in both modes so that the configuration dump can be obtained regardless of how the program is invoked. |
| `onlycompile` | On — this table describes the options that apply while the `-c` flag is active. |
| `queryfile` | The name of the query file to compile. |
| `quiet` | Tests only the compilation process itself, without presenting results. The other presentation options are not started. Included for development purposes. |
| `dot` | Creates a text file in DOT format describing the hierarchical structures produced by the compiler. The file can be passed to the Graphviz tool to generate a graphical description of the dependencies. |
| `csv` | Exports the hierarchical data structures to a CSV file (comma-separated values). |
| `fields` | Adds, to the DOT graph, the fields and their types for each data stream. |
| `tags` | Adds, to the DOT graph, the internal-language programs that build the fields of each query. Must be called together with `fields` — it visually links the fields to their programs. |
| `streamprogs` | Adds, to the DOT graph, the stream-algebra programs that build each query's streams. |
| `rules` | Adds alerting rules to the graph. |
| `hideruleprog` | Hides the programs describing the alerting conditions (used together with `rules`). |
| `transparent` | Generates the graph with a transparent background. |
| `diagram` | Generates marble diagrams. The argument takes the form `type:cycle_count`: `type` (`0` or `1`) determines whether the diagrams show timestamps; `cycle_count` sets the number of cycles shown in the diagram. |

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
