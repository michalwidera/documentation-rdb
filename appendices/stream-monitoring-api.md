# Stream Monitoring API

The optional client API monitors streams from a running, explicitly named `xretractor` instance on the same Linux host. Its transport layer starts `xqry --jsonl` processes, so the API does not duplicate the Boost IPC protocol and follows the command-line tool's rules for selecting streams and ending subscriptions.

The following interfaces are available:

- a Python 3.10+ package with no runtime dependencies beyond the standard library;
- a static C++23 library with a public header and CMake configuration;
- a versioned JSON Lines v1 contract that can also be consumed without either library.

The API does not start the server, load plans, reconnect after failure, or replay missed samples. It is a live observation interface, not a durable or lossless transport.

## JSON Lines v1 contract

`xqry --jsonl` supports four read-only commands:

```bash
xqry --server laboratory --jsonl --hello
xqry --server laboratory --jsonl --dir
xqry --server laboratory --jsonl --detail temperature
xqry --server laboratory --jsonl --select temperature --elimitqry 10
```

Every stdout line is a complete UTF-8 JSON object with `version: 1` and an `event` field. Diagnostic messages go to stderr.

| Event | Contents |
| --- | --- |
| `pong` | Response to `hello`. |
| `streams` | An array of `{name, delta}` items; empty for an idle server. |
| `schema` | Stream name, interval, original query, and ordered fields. |
| `record` | Stream name and a flattened value array. |
| `end` | Normal completion: `limit` or `server_stopped_or_reloaded`. |
| `error` | Stable error code and description; the process exits non-zero. |

A subscription emits its schema first, then records, and exactly one final `end` or `error` event. EOF without a final event is a process error even when the exit code is zero.

```json
{"version":1,"event":"schema","stream":"temperature","delta":"1/20","query":"...","fields":[{"name":"v","type":"INTEGER","count":2}]}
{"version":1,"event":"record","stream":"temperature","values":["21",null]}
{"version":1,"event":"end","reason":"limit"}
```

The schema's `count` field is the scalar cardinality. Numeric arrays preserve every element and its individual `NULL` value; `STRING[N]` remains one string. Non-null wire values are strings interpreted according to the schema type. This preserves rational numerators and denominators and distinguishes the string `"null"` from JSON `null`.

| RQL type | Python | C++ `Value` |
| --- | --- | --- |
| `NULL` | `None` | `std::monostate` |
| `BYTE`, `INTEGER`, `UINT` | `int` | `std::int64_t` |
| `FLOAT`, `DOUBLE` | `float` | `double` |
| `RATIONAL` | `fractions.Fraction` | `Rational` |
| `INTPAIR` | pair of integers | `std::pair<int64_t, int64_t>` |
| `IDXPAIR` | string-integer pair | `std::pair<std::string, int64_t>` |
| `STRING` | `str` | `std::string` |

Messages carry neither a source timestamp nor a durable sequence number. Floating-point precision is limited by the existing textual IPC serialization, and the complete INFO wrapper must fit the server queue's 1024-byte limit.

`--idle-timeout N` ends JSONL after N milliseconds without a record; zero disables the limit. This is independent of the per-read timeout exposed by the libraries.

## Python

Install the package from source:

```bash
python3 -m venv .venv-api
.venv-api/bin/python -m pip install ./api/python
```

Every subscription owns a child `xqry` process:

```python
from retractordb import Client, ReadTimeout

with Client("laboratory", xqry="/path/to/xqry") as db:
    print(db.streams())
    print(db.describe("temperature"))
    with db.subscribe("temperature", limit=10) as samples:
        for record in samples:
            print(record["v"])
        print(samples.end_reason)
```

`Client(server, xqry="xqry", timeout=5.0)` accepts a timeout in seconds. `subscribe(stream, limit=0, idle_timeout=0.0, capacity=1024)` returns an object whose schema is already known when the call returns. `next(timeout=...)` may raise `ReadTimeout` without closing the subscription; ordinary iteration waits indefinitely. A record maps each field name to a scalar or an array of elements.

Use context managers or call `close()` explicitly. Merely breaking out of a `for` loop does not close the iterator. The library does not install signal handlers for the application.

## C++

The library requires C++23. Its targets are available on demand in the RetractorDB tree:

```bash
cmake --build build/Debug --target rdb_monitor
build/Debug/api/cpp/rdb_monitor laboratory temperature 10 /path/to/xqry
```

A project may include the sources directly:

```cmake
add_subdirectory(/path/to/retractordb/api/cpp rdb-api)
target_link_libraries(my_monitor PRIVATE RetractorDB::client)
```

After installing the API component, a CMake package is available:

```cmake
find_package(RetractorDBClient CONFIG REQUIRED)
target_link_libraries(my_monitor PRIVATE RetractorDB::client)
```

Minimal subscription:

```cpp
#include <iostream>
#include "retractordb/client.hpp"

int main() {
  retractordb::Client db("laboratory");
  auto samples = db.subscribe("temperature", {.limit = 10});
  while (auto record = samples.next())
    std::cout << record->values.at("v").size() << '\n';
}
```

`SubscribeOptions` exposes `limit`, `idleTimeout`, and `capacity`. `next(timeout)` returns `std::optional<Record>`; an empty value means normal completion or an explicit close. Errors throw `retractordb::Error` with a stable `code` field. Subscription handles are movable but not copyable; the destructor and `close()` terminate and reap their child process.

## Limits and error handling

Library buffers are bounded: by default, 1024 pending events, 1 MiB per JSONL line, and 64 KiB of retained stderr. An application-buffer overflow produces `buffer_overflow` and closes the subscription without silently dropping records. A server-side queue overflow is a limitation of the existing IPC and may surface only as an idle timeout.

Closing is idempotent: the library sends SIGTERM to its own `xqry`, waits for up to one second, then uses SIGKILL if necessary and reaps the process. Closing a client closes all of its subscriptions; it never sends `xqry --kill` to the server.

Error codes include `read_timeout`, `idle_timeout`, `buffer_overflow`, `stream_not_found`, `no_active_plan`, `server_stopping`, `server_no_response`, `client_queue_missing`, `disconnected`, `communication_error`, `protocol_error`, `spawn_error`, `process_exit`, `process_timeout`, and `closed`.

## Building and testing

The API is developed with the engine but remains optional. Plain `ninja`, `ninja install`, `ninja test`, and `ninja package` do not build, install, test, or package the API.

| Command | Effect |
| --- | --- |
| `ninja install-withapi` | Builds and installs the engine and the `api` component. |
| `ninja test-api` | Builds the test client and runs `ctest -L api`. |
| `cmake -DRDB_WITH_API=ON .` | Adds the `api` component to CPack packages and API tests to the ordinary `test` target. |

The C++ API is always configured, but its targets use `EXCLUDE_FROM_ALL`. `xqry` has its own Boost.JSON translation unit, so the engine does not link anything from `api/`. The dependency runs only from the API to the public `xqry` process interface.

The `st_api_fake` and `st_api_real` tests cover both languages. The former covers types, `NULL`, malformed output, overflow, and process cleanup. The latter uses a real `xretractor` and checks independent subscriptions, arrays, rational numbers, a missing stream, and server shutdown.
