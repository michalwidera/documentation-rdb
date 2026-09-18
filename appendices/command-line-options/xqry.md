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

Without this option, the client reads the `xrdbbus` bus. When exactly one instance is live, it is selected automatically. With several instances, `--select` and `--detail` are routed to the owner of the named stream. Instance-wide commands (`--hello`, `--dir`, `--kill`, and `--reset`) are ambiguous and require `--server`.

Ad hoc routing examines sources in `FROM`, or the stream in `ON` for a `RULE`. They must all belong to one server. A `DECLARE` has no addressee, so with several instances it also requires `--server`. A misspelled name and a query crossing server boundaries are rejected before a command is sent.

## Listing instances: `--bus`

`xqry --bus` reads the bus without contacting the servers. Rows are sorted by name, and `(unnamed)` denotes a backward-compatible instance started without a name.

```text
$ xqry --bus
SERVER | PID    | MODE | QUERY               | STREAMS
-------+--------+------+---------------------+-----------
alpha  | 249247 | N    | .../plans/alpha.rql | srca, dsta
beta   | 249248 | FS   | .../plans/beta.rql  | srcb, dstb
MODE: N=normal, R=realtime, F=no-clock, U=until-eof, M=llimitqry, X=xqrywait, S=service
```

The table shortens paths for readability. `--bus --yaml` preserves the complete path:

```yaml
---
apiVersion: xqry/v1
servers:
  - name: alpha
    pid: 249247
    modes: N
    query: "/home/user/plans/alpha.rql"
    streams:
      - srca
      - dsta
```

An empty bus produces a valid `servers: []` YAML document. The diagnostic that there are no instances is written to `stderr`.

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

## Receiving data

| Option | Meaning |
| --- | --- |
| `-s` / `--select stream` | Subscribes to current records of the stream. |
| `-m` / `--elimitqry N` | Stops after exactly N records; `0` means no limit. |
| `-n` / `--null` | Skips records in which all values are `NULL`. |
| `-c` / `--needctrlc` | Requires Ctrl+C instead of stopping on any keypress. |

Each subscription creates its own response queue. When the server stops or replaces its plan, it sends an end marker and the client closes reception. A sudden failure without a marker is detected by the `timing.query_no_data_timeout_ms` timeout.

### Presentation formats

| Option | Format |
| --- | --- |
| `-r` / `--raw` | Undecorated text, used by default. |
| `-g` / `--graphite` | Graphite-compatible rows. |
| `-f` / `--influxdb` | InfluxDB line protocol. |
| `-p` / `--gnuplot x,y` | Data and commands for feeding gnuplot directly. |
| `-z` / `--gnuplot-rtl` | A gnuplot modifier that puts the newest samples on the right. |

Only one format may be selected. `--gnuplot-rtl` requires `--gnuplot`. Raw format sends all array-field elements and preserves the `NULL` map per element.

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

Before changing the active model, the server parses and compiles the set and reserves its stream names, storage files, and rotation counter. Rejection does not stop the old plan. An accepted plan becomes active at the end of the current slot, old subscriptions receive an end marker, and artifacts from the previous epoch are cleaned up according to startup and rotation rules. An empty file switches the server to idle state.

When the target is a service instance, accepted contents are also written to its startup file so they survive a process restart.

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

Typical test pattern:

```bash
xretractor query.rql --name test --llimitqry 100 --noanykey --xqrywait &
xqry --server test --wait-server --select stream --elimitqry 10
```

## Version information

The information below the help list contains the branch name, commit hash, compiler version, build time and type, and the log path. The format is described in [xretractor - Version Information](xretractor.md#version-information).
