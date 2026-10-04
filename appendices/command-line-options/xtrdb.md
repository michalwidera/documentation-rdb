# xtrdb

The `xtrdb` program is an interactive tool for analyzing artifacts and substrates written by RetractorDB. It mostly works in interactive mode (a REPL), but it also offers a few startup options (e.g. `--help`, `--noprompt`, `--storagemap`).

> **⚠️ Warning**
>
> Interactive and batch `xtrdb` modes refuse to run while any `xretractor` instance in the lock directory is running, including named instances. Stop those instances or wait for them to finish. The tool reads the same `paths.lock_dir` TOML setting as the engine (by default, the process temporary directory), scans the `xretractor_service*.lock` family, and checks whether a lock is held. A stale lock file alone does not cause refusal. For a custom lock directory, run `xtrdb` with the same configuration as the server. The `--help` and `--storagemap` options return before this check; `--storagemap` only reads storage state.


---

## Running it

```
$ xtrdb                    # interactive mode (with a prompt)
$ xtrdb -n                 # batch mode (no prompt, no "ok")
$ xtrdb --noprompt         # same as -n
$ xtrdb noprompt           # backward compatibility (legacy, positional argument)
$ xtrdb -s data_file       # show the storage structure for the given file
$ xtrdb --storagemap file  # same as -s
$ xtrdb -h                 # help and build information, then exit
```

The `-n/--noprompt` mode removes highlighting, the `.` prompt, and the `ok` message - useful when input comes from a file or a pipe. The legacy positional variant `noprompt` still works too.

```
$ xtrdb -n < script.xtrdb
```

The `-s/--storagemap` option only runs the data-file structure report and exits the program (without entering the REPL).

Once started, the tool prints a `.` prompt and waits for a command. Every command ends with pressing Enter.

---

## Command overview

The `help` or `h` command shows the list of available commands:

```
$ xtrdb
.help
exit|quit|q                     exit
quitdrop|qd                     exit & drop artifacts (data, .desc, .meta)
open file [schema]              open or create database with schema
                                example: .open test_db { INTEGER data 
                                STRING name[3] }
storage [path]                  set storage path for database
policy [name]                   set storage policy
dropfile [file1] [file2] ... }  remove listed file(s), end with }
desc|descc                      show schema
read|rread [n]                  read record from database into payload
write [n]                       from payload send record to database
purge                           remove all records from database
append                          append payload to database
set [field][value]              set payload field value
setpos [position][number value] set payload field number value
getpos [position]               show payload field value
status                          show current payload status
rox                             remove on exit flip (data, .desc, .meta)
print|printt                    show payload
list|rlist [count]              print first records
input [[field][value]]          fill payload
hex|dec                         type of input/output of byte/number fields
size                            show database size in records
cap [value]                     set device stream backread capacity
dump                            show payload memory
meta                            show meta index (null patterns) for open db
metaraw                         show internal meta file structure
echo                            print message on terminal
system                          execute system command
#|rem [text]                    comment line
help|h                          show this help
```

---

## Session management

| Command           | Description                                                             |
| ------------------- | ---------------------------------------------------------------- |
| `exit`, `quit`, `q` | Exit the tool. Written records remain on disk unless deletion was enabled through `rox`; changes made only in the payload buffer are not saved automatically. |
| `quitdrop`, `qd`    | Exit and delete the open artifact files (data, `.desc`, `.meta`). A data file referenced by `REF` in `.desc` outside the storage directory and `storage.ref_dirs` is kept - only `.desc` is deleted. |

---

## Environment configuration

| Command           | Description                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------- |
| `storage [path]` | Set the working directory. Subsequent `open` commands look for the file at this path.                  |
| `policy [name]`    | Set the storage policy (`DEFAULT`, `DIRECT`, `POSIX`, `MEMORY`, …). Must precede `open`. |

TOML configuration is loaded from the standard locations: `/etc/retractor/retractor.toml`, then `$XDG_CONFIG_HOME/retractor/retractor.toml` or `~/.config/retractor/retractor.toml`. `xtrdb` has no `--config` option; for a custom lock directory or `storage.ref_dirs` setting, place those keys in one of these layers.

---

## Opening an artifact

```
open file_name
open file_name { TYPE field TYPE field ... }
```

If a `.desc` file exists, the schema is read from it. If not, the schema must be given in `{}`.

If the data file cannot be opened, `open` prints the reason (such as `cannot open output file`) and leaves the storage unopened instead of terminating the process. If the attempt created a new `.desc` file but failed to open the data file, that descriptor file is removed. After fixing the cause, `open` can be retried.

The `REF` field in an existing `.desc` points to the data file and may lead outside the directory set by the `storage` command - this is how the engine describes external `BINFILE`, `TEXTFILE`, and `DEVICE` sources, which `xtrdb` reads without restrictions. For a writable store (`DEFAULT`, `DIRECT`, `POSIX`, and others) whose `REF` points outside that directory, `open` refuses to open it: the diagnostic names the `.desc` and the data file, and refusal occurs before the file is created. Such writes can be allowed through the TOML configuration key `storage.ref_dirs` - a list of absolute directory paths where a `REF` from `.desc` may place the data file (see [xretractor options](xretractor.md#configuration-file-toml)). An invalid entry in this list stops `xtrdb` at startup with `Configuration error: storage.ref_dirs ...`. A `REF` supplied in the schema of `open name { ... }` is the operator's decision and is not subject to this restriction.

Array field types: `STRING name[8]` means a text field 8 bytes long (array multiplicity = 8).

Examples:

```
.open str1                          # schema from the file str1.desc
.open dump.tmp { INTEGER value }    # schema given manually
.open results { INTEGER a FLOAT b STRING name[8] }
```

---

## Reading and writing records

| Command | Description                                                       |
| --------- | ---------------------------------------------------------- |
| `read N`  | Read record N (0-based) from the file into the payload buffer.     |
| `rread N` | Like `read`, but reads from the end of the file (reverse read).   |
| `write N` | Write the current payload to record N in the file.               |
| `append`  | Append the current payload as a new record at the end of the file.    |
| `purge`   | Delete all records from the file (truncate the file to 0 records). |

An index outside the range of a result store, including an empty store, is rejected before reading: `read` and `rread` print `record out of range - read command`, leaving the payload and its previous state unchanged. `list` and `rlist` print `record out of range - list command` and move on to the next index. If the range check allows the request but the read itself reports a missing record or an error, the payload state changes to `error`; `list` and `rlist` then print `fetch error`. For declared sources, `read` and `rread` skip the initial range check and use the source's read result. The state can be checked with `status`.

A successful `write N` or `append` sets the payload state to `stored`. Attempting `append` on a declared `BINFILE`, `TEXTFILE`, or `DEVICE` source that supports only reading sets the state to `error`: the source data and record count remain unchanged, and `xtrdb` continues accepting commands. The payload state reported by `status` is separate from the process exit code; this refusal does not require an error exit. Other write failures, such as an I/O error, may terminate the process.

The write-state and read-only append-refusal contract is covered by the `it_xtrdb_write_status-run` integration test.

---

## Browsing content

| Command | Description                                                                     |
| --------- | ------------------------------------------------------------------------ |
| `list N`  | Print the first N records (from the beginning), one row per record. |
| `rlist N` | Like `list`, but reads from the end of the file.                                |
| `print`   | Print the current payload in multi-line format.                                 |
| `printt`  | Print the current payload on a single line.                                 |
| `size`    | Print the record count and the size of a single record, in bytes.              |
| `dump`    | Print the raw bytes of the current payload in hex format.                    |
| `desc`    | Print the field schema of the open artifact (multi-line).                   |
| `descc`   | Print the schema on a single line (compact).                               |

---

## Editing the payload

| Command          | Description                                                                               |
| ------------------ | ---------------------------------------------------------------------------------- |
| `set field value` | Set the field with the given name in the payload buffer.                                     |
| `setpos N value` | Set the field at index N (0-based) in the payload buffer.                               |
| `getpos N`         | Print the value of the field at index N from the current payload.                              |
| `input`            | Interactively fill the payload - enter values in order for each field.       |
| `status`           | Print the payload's state: `clean`, `fetched`, `changed`, `stored`, `error`.                      |
| `hex` / `dec`      | Toggle numeric field input/output between hexadecimal and decimal. |

---

## Null metadata (`.meta`)

| Command | Description                                                                                                             |
| --------- | ------------------------------------------------------------------------------------------------------------------ |
| `meta`    | Print the null and transmission-gap index from the `.meta` file - descriptively (segments with a record count and null pattern).  |
| `metaraw` | Print the raw binary structure of the `.meta` file - every RLE entry with its `count`, `gap`, `bitsetHex` fields.             |

`meta` shows segments with information about nulls and transmission gaps (`gap`). `metaraw` shows the raw binary structure of the `.meta` file.

---

## Other commands

| Command            | Description                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------- |
| `rox`                | Toggle the "remove on exit" flag - deletes the data, `.desc`, and `.meta` when the tool exits; a data file outside the storage directory and `storage.ref_dirs` is kept, as with `quitdrop`. |
| `cap N`              | Set the backread buffer capacity for stream devices.                     |
| `dropfile f1 f2 … }` | Delete the listed files. The list ends with the token `}`.                                     |
| `echo text`         | Print text to the terminal (useful in scripts).                                        |
| `system command`   | Invoke a shell command.                                                               |
| `#` or `rem`        | A comment line (ignored). `#` doesn't even print a prompt.                           |

---

## Usage examples

### Previewing an artifact

```
$ xtrdb
.storage temp
.open str1
.size
.list 10
.quit
```

### Reading a DUMP file without a descriptor

Dump files created by `DO DUMP` have no `.desc` file - the schema must be specified manually:

```
$ xtrdb
.open results_alarm_dump.tmp { INTEGER value }
.size
.list 6
.quit
```

A dump has no `.meta` file either, so the `meta` and `metaraw` commands have nothing to show for it. This means the printed values are everything the file carries: a zero in a dump may be a genuine zero, a `NULL` field, or a record the engine did not have, and a transmission gap leaves no marker there at all. The dump contract is described in [Alerting implementation](../../query-execution/alerting-implementation.md#the-dump-contract-values-only-no-null-and-no-gaps).

### Batch script

```bash
xtrdb noprompt << 'EOF'
storage /var/retractor
open sensor_dump.tmp { INTEGER a FLOAT b }
list 20
quit
EOF
```

### Inspecting null metadata

```
.open str1
.meta
.metaraw
```
