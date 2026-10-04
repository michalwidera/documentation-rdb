# xqry

The `xqry` program communicates with a running `xretractor` process through Boost IPC. It reads current records, displays plans and schemas, attaches individual RQL statements, replaces a complete plan, and stops a selected instance. Several `xqry` processes can run at the same time, including against different servers.

## Running it

```text
$ xqry -h
xqry - data query tool.

Usage: xqry [option]

Allowed options:
  -s [ --select ] arg            show this stream
  -t [ --detail ] arg            show details of this stream
  -a [ --adhoc ] arg             adhoc query mode
  -q [ --reset ] arg             replace the whole plan of the target instance
                                 with this RQL file
  -m [ --elimitqry ] arg (=0)    limit of elements, 0 - no limit
  -n [ --null ]                  if null row appear - skip it in output
  -l [ --hello ]                 diagnostic - hello db world
  -k [ --kill ]                  kill xretractor server
  -d [ --dir ]                   list of queries
  -y [ --yaml ]                  yaml output format for --dir, --detail and
                                 --bus
  -j [ --jsonl ]                 versioned JSON Lines API output
  -i [ --idle-timeout ] arg (=0) JSONL idle timeout in ms; 0 disables
  -r [ --raw ]                   raw output mode (default)
  -g [ --graphite ]              graphite output mode
  -f [ --influxdb ]              influxDB output mode
  -p [ --gnuplot ] arg           x,y - gnuplot output mode
  -z [ --gnuplot-rtl ]           gnuplot output: newest samples on the right
  -o [ --gnuplot-ohlc ]          gnuplot output: row = open, high, low, close,
                                 then the samples of that candle
  -e [ --config ] arg            config file (TOML); overrides search
  -h [ --help ]                  produce help message
  -c [ --needctrlc ]             force ctl+c for stop this tool
  -w [ --wait-server ]           poll until xretractor server is available
  -x [ --server ] arg            target xretractor instance name
  -b [ --bus ]                   list live xretractor instances and their streams
```

## Selecting an instance

An explicit `--server name` selects an instance without automatic routing:

```bash
xqry --server measurements --dir
xqry --server measurements --select temperature
xqry --server measurements --kill
```

Without this option, the client reads the bus in the current namespace: the default `xrdbbus_v7`, or `xrdbbus_v7_<namespace>` when `RDB_NAMESPACE` is set. When exactly one instance is live, it is selected automatically. With several instances, `--select` and `--detail` are routed to the owner of the named stream. Instance-wide commands (`--hello`, `--dir`, `--kill`, and `--reset`) are ambiguous and require `--server`. The combined `--bus` listing described below does not change this routing.

Ad hoc routing examines sources in `FROM`, or the stream in `ON` for a `RULE`. They must all belong to one server. A `DECLARE` has no addressee, so with several instances it also requires `--server`. A misspelled name and a query crossing server boundaries are rejected before a command is sent.

## Listing instances: `--bus`

`xqry --bus` discovers accessible buses of the current version without requiring `RDB_NAMESPACE` and prints a separate `NAMESPACE:` section for each bus with at least one live instance. It behaves the same way when `RDB_NAMESPACE` is set: the listing covers all accessible namespaces, while other commands still use the current namespace. `(default)` denotes the bus without a namespace, and `(unnamed)` denotes a backward-compatible instance started without a name. Sections are ordered by bus name, with the default first; instances within a section are sorted by name.

The client reads the shared-memory registries without contacting servers. It omits segments with no live instances. Shared-memory permissions limit discovery to buses accessible to the current account.

```text
$ xqry --bus
NAMESPACE: (default)
SERVER | PID    | MODE | QUERY               | STREAMS
-------+--------+------+---------------------+--------
alpha  | 249247 | N    | .../plans/alpha.rql | srca
       |        |      |                     | dsta
MODE: N=normal, R=realtime, F=no-clock, U=until-eof, M=llimitqry, X=xqrywait, S=service

NAMESPACE: bus_probe
SERVER | PID    | MODE | QUERY | STREAMS
-------+--------+------+-------+--------
probe  | 249249 | N    | -     | -
MODE: N=normal, R=realtime, F=no-clock, U=until-eof, M=llimitqry, X=xqrywait, S=service
```

The table shortens paths for readability. `--bus --yaml` preserves the complete path and keeps one `servers` list. Each entry has a `namespace` field: `null` means the default bus, and a named namespace is a quoted string.

```yaml
---
apiVersion: xqry/v1
servers:
  - name: alpha
    namespace: null
    pid: 249247
    modes: N
    query: "/home/user/plans/alpha.rql"
    streams:
      - srca
      - dsta
  - name: probe
    namespace: "bus_probe"
    pid: 249249
    modes: N
    streams: []
```

When no accessible bus has a live instance, table output on `stdout` is empty and YAML contains `servers: []`. The `xqry: no live xretractor instance` message goes to `stderr`.

## Stream list and details

`--dir` prints an aligned table:

```text
$ xqry --server alpha --dir
name  | duration | size | count | location      | cap
------+----------+------+-------+---------------+----
core0 | 1/10     | -1   | 0     | datafile2.dat | 4
str1  | 1/30     | 0    | 0     |               | 0
```

`duration` is the stream's exact interval, `size` the amount of stored data, `count` the record count, `location` the source file, and `cap` the history capacity computed by the compiler. A declared source has `size` equal to `-1`.

`--detail stream` shows the original query and its fields. The `--yaml` modifier switches `--dir`, `--detail`, and `--bus` to an `apiVersion: xqry/v1` document; it is not a command on its own. An unknown stream exits with code `2`.

Command responses are matched to the client's specific request. The `ipc.client_response_max_fails` time budget covers sending the command and receiving its response; a full command queue causes a refusal when that deadline expires. A response abandoned by a killed client can be reclaimed without blocking later clients.

## Receiving data

| Option | Meaning |
| --- | --- |
| `-s` / `--select stream` | Subscribes to current records of the stream. |
| `-m` / `--elimitqry N` | Stops after exactly N records; `0` means no limit. |
| `-n` / `--null` | Skips records in which all values are `NULL`. |
| `-c` / `--needctrlc` | Requires Ctrl+C instead of stopping on any keypress. |

Each subscription creates its own response queue. When the server stops or replaces its plan, it sends an end marker and the client closes reception. A sudden failure without a marker is detected by the `timing.query_no_data_timeout_ms` timeout.

### Reception or rendering failure

An exception in the receive/render loop for presentation formats ends the subscription with a client error, even if some records have already been printed. The client stops reception, waits for the receiving thread to finish, and returns `renderFailed`. Standard error shows `select loop failed in the client; reason in the client log`, while the client log contains the stream name and the cause of the exception. The exit code corresponds to `EINTR` (`interrupted`). Records received before the failure are a partial result and do not indicate successful completion of the subscription.

Diagnostics and the exit code for this path are covered by the `it_select_loop_failure-run` integration test.

### Presentation formats

| Option | Format |
| --- | --- |
| `-r` / `--raw` | Undecorated text, used by default. |
| `-g` / `--graphite` | Graphite-compatible rows. |
| `-f` / `--influxdb` | InfluxDB line protocol. |
| `-p` / `--gnuplot x,y` | Data and commands for feeding gnuplot directly. |
| `-z` / `--gnuplot-rtl` | A gnuplot modifier that puts the newest samples on the right. |
| `-o` / `--gnuplot-ohlc` | A gnuplot modifier that draws a candlestick chart: the record is open, high, low, close, followed by that candle's samples. |

Only one format may be selected. `--gnuplot-rtl` and `-o` / `--gnuplot-ohlc` require `--gnuplot` and can be combined. In `--gnuplot-ohlc` mode the first `-p` parameter counts samples, not candles; the record layout and the drawing rules are described in the [Candlestick Chart (OHLC)](../../usage-examples/candlestick-chart-ohlc.md) example. Raw format sends all array-field elements and preserves the `NULL` map per element.

In OHLC output, records without valid candle values do not produce candles, but may still produce a sample line. If the current window has no valid candles, `xqry` sends only the sample series; if it has no valid samples, only the candle series. A window with no valid points sends no empty `plot` command to gnuplot.

## Ad hoc commands

`--adhoc` attaches exactly one `SELECT`, `DECLARE`, or `RULE` to the active plan:

```bash
xqry --server measurements --adhoc \
  "SELECT AVG(value : 10) STREAM avg10 FROM sensor"
```

Compiler directives and several statements in one request are rejected. Logical origin, source declarations, rules, and resource claims are described in [Ad Hoc Queries](../../query-execution/ad-hoc-queries.md).

## Replacing the complete plan: `--reset`

`--reset file.rql` sends the file contents and replaces the complete plan of the selected instance. This differs from ad hoc attachment: a complete set may contain several statements, rules, and the `:STORAGE`, `:SUBSTRAT`, and `:ROTATION` directives.

```bash
xqry --server service --reset plan.rql
```

Before changing the active model, the server parses and compiles the set, checks retained `.desc` files (always for `DECLARE` sources, and under `:ROTATION` for `SELECT` outputs and substrates), checks retained storage compatibility and whether disk output files can be opened, and reserves its stream names, storage files, and rotation counter. File validation does not create them; a refusal, such as `descriptor parse failed` with the file path and error location or `cannot open output file`, neither stops the old plan nor changes the service startup file. An accepted plan becomes active at the end of the current slot, old subscriptions receive an end marker, and artifacts from the previous epoch are cleaned up according to startup and rotation rules. An empty file switches the server to idle state.

The file check is preliminary: a path may change between the `OK` response to `--reset` and the actual storage open. A late open failure during the plan swap is not currently returned to the client as a refusal and may stop the server; `OK` does not guarantee that this later operation will succeed.

When the target is a service instance, accepted contents are also written to its startup file so they survive a process restart.

### The `DO SYSTEM` rule does not pass through this channel

A plan carrying a `DO SYSTEM` rule is refused as a **whole**, naming the rule and the reason:

```
$ xqry --reset with-system-rule.rql --server service
xqry: plan reload refused at reset-commit: Rejected: rule 'evil' on stream 'alpha' uses DO SYSTEM; ...
```

The reason is the same one that makes the ad-hoc channel refuse it: `DO SYSTEM` runs an arbitrary shell command under the instance's account, and the IPC channel carries no authorship, so it does not make the sender of a reset the operator of the service. Such a rule may only be asked for in the plan file the instance starts from. The refusal covers the whole set rather than the single rule, because accepted contents are written to the service's startup file, whose start-up passes no such check - a rule cut out in flight would come back armed after the next restart.

An operator who deliberately hands this channel over sets `service.unrestricted = true` in the TOML configuration (→ [xretractor](xretractor.md#configuration-file-toml)). The instance then leaves a warning in the log at every start, and the ad-hoc channel stays closed regardless of that value.

## JSON Lines for applications

`--jsonl` exposes versioned machine-readable output for `--hello`, `--dir`, `--detail`, and `--select`. It requires an unambiguous server; applications should always specify it.

```bash
xqry --server laboratory --jsonl --hello
xqry --server laboratory --jsonl --dir
xqry --server laboratory --jsonl --detail temperature
xqry --server laboratory --jsonl --select temperature --elimitqry 10
```

Each stdout line is a complete JSON object with `version: 1` and an `event` field. Supported events are `pong`, `streams`, `schema`, `record`, `end`, and `error`. Diagnostics go to `stderr`. `--idle-timeout N` specifies in milliseconds how long a subscription may wait without a record; zero disables the limit.

Mutating commands, `--bus`, YAML, other output formats, `--null`, and `--wait-server` cannot be combined with JSONL. The complete contract and ready-made Python and C++ clients are described in [Stream Monitoring API](../stream-monitoring-api.md).

## One command at a time

`--select`, `--detail`, `--adhoc`, `--reset`, `--dir`, `--bus`, and `--hello` are distinct commands; passing several at once exits with code `22`. `--kill` can deliberately be combined with `--select -m N` or with `--adhoc` to stop the server after the operation.

## Waiting for a server

`--wait-server` polls IPC availability according to `timing.server_startup_wait_s` and `timing.server_startup_poll_ms`. With an explicit name, it waits for that instance. Without a name it repeats routing: historically it waits for an unnamed instance, but after one named instance appears, it selects that instance automatically. Ambiguity with several servers is reported immediately. `--bus` needs no server and ignores waiting.

Readiness requires openable IPC objects and a live instance on the bus. If the bus is unavailable, the held IPC identity lock is checked instead. Objects left behind after a crash alone do not mean the server is ready.

Typical test pattern:

```bash
xretractor query.rql --name test --llimitqry 100 --noanykey --xqrywait &
xqry --server test --wait-server --select stream --elimitqry 10
```

## Version information

The information below the help list contains the branch name, commit hash, compiler version, build time and type, and the log path. The format is described in [xretractor - Version Information](xretractor.md#version-information).
