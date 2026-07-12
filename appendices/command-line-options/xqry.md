# xqry

The `xqry` program is an integral part of RetractorDB. It shares a memory area (Boost IPC) with `xretractor`, used for communication. It's used to query the running processing process, receive results from the query loop, and control the server's operation.

Unlike `xretractor`, `xqry` can be run in multiple instances at once.

## Running it

```
$ xqry -h
xqry - data query tool.

Usage: xqry [option]

Allowed options:
  -s [ --select ] arg         show this stream
  -t [ --detail ] arg         show details of this stream
  -a [ --adhoc ] arg          adhoc query mode
  -m [ --tlimitqry ] arg (=0) limit of elements, 0 - no limit
  -n [ --null ]               if null row appear - skip it in output
  -l [ --hello ]              diagnostic - hello db world
  -k [ --kill ]               kill xretractor server
  -d [ --dir ]                list of queries
  -y [ --diryaml ]            list of queries in yaml format
  -r [ --raw ]                raw output mode (default)
  -g [ --graphite ]           graphite output mode
  -f [ --influxdb ]           influxDB output mode
  -p [ --gnuplot ] arg        x,y or x,ymin,ymax - gnuplot output mode
  -h [ --help ]               produce help message
  -c [ --needctrlc ]          force ctl+c for stop this tool
  -w [ --wait-server ]        poll until xretractor server is available
```

---

## Receiving data from streams

| Option                   | Meaning                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------- |
| `-s` / `select arg`     | Receives data from the given stream exposed by `xretractor`.                                       |
| `-t` / `detail arg`     | Shows detailed information about a stream: its name, delta, query text, and field list with types (YAML).   |
| `-a` / `adhoc arg`      | Attaches a query to the system while it's running (ad hoc mode).                                        |
| `-m` / `tlimitqry arg`  | Limits the number of results received. A value of `0` means no limit. Especially useful with the `-k` option.   |
| `-n` / `null`           | Skips rows where every field is null. Useful for streams with measurement gaps — it removes noise from the output without client-side filtering. |

Example response for the `detail` option:

```yaml
---
apiVersion: xqry/v1
stream:
  name: str4
  delta: 1
  query: SELECT (str4[0]+1)*2 STREAM str4 FROM core0>1
  fields:
    str4.str4_0:
      type: INTEGER
```

---

## Diagnostics and server control

| Option              | Meaning                                                                              |
| ------------------ | -------------------------------------------------------------------------------------- |
| `-l` / `hello`          | Verifies the communication channel with `xretractor` (a diagnostic ping).      |
| `-k` / `kill`           | Requests that the `xretractor` process stop.                                              |
| `-d` / `dir`            | Lists all queries running in `xretractor`, in text format. |
| `-y` / `diryaml`        | Lists all queries in YAML format.                                       |
| `-w` / `wait-server`    | Polls every 100 ms whether `xretractor` is available (up to 30 s), and once confirmed, carries out the requested command. Allows `xqry` to be started reliably in startup scripts and containers when process start order isn't guaranteed. Only checks IPC availability — it doesn't send any command to the server, and doesn't trigger data processing. |

---

## Output formats

`xqry` supports four data-presentation formats. The format is chosen with a flag — it can be combined with the `select` option.

| Option              | Format         | Use case                                                                 |
| ------------------ | -------------- | ---------------------------------------------------------------------------- |
| `-r` / `raw`       | Text       | The default. Undecorated data — useful for scripts and piping.          |
| `-g` / `graphite`  | Graphite       | The `metric value timestamp` format — ready to send to Graphite.    |
| `-f` / `influxdb`  | InfluxDB       | InfluxDB line protocol — ready to import into a time-series database.       |
| `-p` / `gnuplot x,y` or `x,ymin,ymax` | Gnuplot | Aggregates for direct feeding into `gnuplot`. The argument `x,y` gives the time axis and the value; `x,ymin,ymax` additionally restricts the Y-axis range. The separator can be `,` or `:`. |

---

## Controlling the receive mode

| Option              | Meaning                                                                                          |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| `-h` / `help`      | Displays the help text.                                                                        |
| `-c` / `needctrlc` | In normal mode, any keypress stops receiving data. This option requires using `Ctrl+C` instead.      |

---

---

## Launch pattern in scripts

When using `xretractor -m N` (a limited number of cycles), there's a risk of a race: the server may process all the data before the client manages to connect. Guaranteed pattern:

```sh
# Server side: -x causes processing to be held off until
# the first command arrives from xqry
xretractor query.rql -m 100 -k -x &

# Client side: -w checks IPC readiness without sending commands,
# so it doesn't accidentally trigger processing
xqry -w -s stream -m 10
```

The `-w` and `-x` flags are complementary:

| Flag             | Tool     | Role                                                                 |
| ----------------- | ------------- | -------------------------------------------------------------------- |
| `-w` / `wait-server` | `xqry`     | Waits for the server's IPC to become ready before sending a command                |
| `-x` / `xqrywait`   | `xretractor` | Holds off processing until the first command arrives from a client   |

Without `xretractor -x`, with fast file-based streams, the data may be processed in full before the client connects — `xqry` will wait for data that never arrives.

---

## Version information

The information at the bottom of the help listing is identical to `xretractor`'s — it includes the repository branch name, compiler version, build time, and the log file path (`/tmp/xqry.log`). A description of the format can be found in the chapter [xretractor — Version Information](xretractor.md#version-information).
