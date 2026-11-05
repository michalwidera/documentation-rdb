# Runtime errors

This chapter describes diagnostics for starting and executing a plan, accessing data and storage, running rules, and communication between `xretractor`, `xqry`, and `xtrdb`. It also covers draining and reusing response queues. RQL authoring errors belong to the separate [Syntax and compilation errors](../query-language-construction/syntax-and-compilation-errors.md) chapter. Successful compilation does not confirm that sources, disk space, shared memory, or the permissions needed during execution are available.

The tables quote characteristic diagnostic fragments. Names, PIDs, sizes, and system causes are filled in at run time. The same client symptom, such as a timeout, can have several causes; identifying it also requires the server log.

## Establishing the effect of an error

Keep the full diagnostic, exit code, instance name, plan, and output of `xretractor --build-info`. Check the instance and client logs for the same period. Outside service mode, logs are created in the process temporary directory; the program reports the effective location. For a systemd unit, also check its journal, for example `journalctl -u xretractor.service`.

| Situation | System response | Next action |
| --- | --- | --- |
| Plan refused before startup, for example an incompatible retained descriptor | `EPROTO` (`71` on Linux). In a systemd unit, startup refusal clears the service plan file. | Correct the plan or its retained files, then deliver it again. |
| Environment failure, such as a missing source or storage I/O error | Usually `EIO` (`5` on Linux); during execution, `FATAL (environment):` or `Engine error (IOError)`. The service plan file is preserved. | Repair access, capacity, or the storage device before restarting. |
| An engine error returned within a slot, other than I/O | `FATAL:` and `Engine error (...)`; the process exits with code `1`, and the unit attempts to clear its plan file. This also applies to a returned `EvalError`. | Keep the cause and a minimal example; check the types and restrictions described below. |
| A Boost.Interprocess exception escaping the execution loop | `IPC::interprocess exception`, exit code `ECHILD`. | Check the preceding IPC diagnostic, resources, and version compatibility. |
| An unexpected standard exception in the execution loop | `IPC Fail.` and its cause; exit code `EINTR`, with the unit plan-clearing path. | The prefix alone does not establish a transport failure; lack of memory is one possible cause. Keep the full diagnostic. |
| Reset, ad hoc, or subscription refusal before acceptance | The error returns to the client; the existing plan may continue running. | Remove the cause and deliberately retry the command. |
| A handled warning or local error, such as one client's damaged queue or a failed `SYSTEM` command | The response depends on the operation; ERROR level alone does not mean process termination. | Use the corresponding section to establish whether a record, subscription, write, or the entire execution was lost. |

In the standard Release configuration, `SPDLOG_WARN` macros are compiled out, while ERROR and CRITICAL remain. This affects warnings about source data, RT settings, and the queue pool, among others. Some RT diagnostics are printed directly to stdout in Release too. Absence of a warning in the log does not confirm valid data or met deadlines. See [Plan refusal versus environment failure](../appendices/command-line-options/xretractor.md#plan-refusal-and-environment-failure) for the service policy.

After SIGABRT or an OOM kill, the process does not perform ordinary cleanup. The current systemd unit runs `xretractor-stop-post`, which attempts to clear the plan and reports `cleared plan after ...` or `cannot clear plan after ...`. This protection requires the installed unit and helper. Check the unit journal, memory limits, and the abort cause; restarting alone does not remove the cause. This policy does not clear an operator's plan file when running outside the unit.

## Configuration, locks, and instance collisions

| Diagnostic or symptom | Cause and response | Remedy and prevention |
| --- | --- | --- |
| `Configuration error:` with a TOML file or key name | Unavailable or malformed configuration, an invalid directory, or a disallowed setting; the program refuses to run. | Check every loaded configuration layer and access as the service account. Correct the indicated key; do not rely solely on the configuration of the user launching the client. |
| `Invalid config ... Using default ...` | Some numeric settings are replaced with defaults; this warning is not a general policy of accepting malformed TOML. | Set a valid value explicitly. Invalid `storage.default_retention` leaves streams without that default retention; invalid `sources.timeout_s` refuses startup. |
| `cannot acquire lock`, `IPC identity lock ... is held`, `is already running` | Another instance holds a lock or a live bus entry has the same identity; the new process does not take over its resources. | Use a different name and disjoint resources, or stop the owner normally. Changing `TMPDIR` or the lock directory does not separate the same explicit IPC identity. |
| `Stream ... is already served`, `Storage file ... is already written`, `Rotation counter file ... is already used` | The plan conflicts with another instance's resources; startup, delivery, or plan replacement is refused. | Separate stream names, writable files, and the rotation counter. A different process name alone is insufficient. |
| Lock-file verification refusal: type, owner, links, or a system error | Exclusive ownership cannot be confirmed safely. | Check the owner and lock directory; use a regular file meeting the requirements. Do not remove a running process's lock. |
| `CRITICAL ERROR: Lost service lock!` | The instance lost the checked lock and ends execution. | Check file removal or replacement by administrators and cleanup tools; preserve the lock's identity throughout the process lifetime. |

An empty service plan and a `no active plan` response are valid idle states. A plan containing only directives can instead reach execution and report `plan holds no streams - only directives`; add an actual stream. See [Multiple instances and the bus](../data-processing-system-architecture/multiple-instances-and-bus.md) for naming and locking rules.

## Sources, storage directory, and descriptors

| Diagnostic fragment | Scenario and effect | Recommended action |
| --- | --- | --- |
| `source file does not exist`, `cannot inspect source`, `cannot read source`, `cannot open TEXTFILE source` | A file disappeared, is not mounted, or is inaccessible to the process account. Pre-start checking reports an environment failure and leaves previous results untouched. | Prepare sources before startup; check the path and directory traversal permissions as the service account. `-c` alone does not check input availability. |
| Source-kind mismatch for `BINFILE`, `TEXTFILE`, or `DEVICE` | Regular files, FIFOs, and character devices are not interchangeable. The plan or the object actually opened is rejected. | Use `BINFILE` or `TEXTFILE` for a file and `DEVICE` for a FIFO or character device. Control the object type created by the producer. |
| `storage: directory ... does not exist`, `is not a directory` | The `STORAGE` directory is missing or the path denotes a different object; this is a plan refusal, including for MEMORY streams. | Create the directory before startup and set appropriate permissions. The engine does not create it from the directive. |
| `cannot open output file`, `cannot inspect output file` | Access denied, a directory instead of a file, a final-component symbolic link, or a path changed after preflight. | Check the account, mount, and free space; use suitable regular files. `O_NOFOLLOW` protects the final name, not the entire directory chain. |
| `descriptor schema mismatch`, malformed/empty `.desc`, unsupported `TYPE`, or mismatched `REF` | A retained descriptor describes a different record, source, or storage profile. Refusal prevents interpreting bytes with an incompatible schema. | Restore a matching plan and file family. Starting a new store after archiving old data must be a deliberate decision. Do not edit only `.desc` to conceal a byte-format mismatch. |
| Writable `REF` refused outside permitted directories | A descriptor directs writes outside the storage directory and `storage.ref_dirs`. | Correct `REF` or explicitly configure a trusted directory. External read-only sources have a different contract. |

Preflight does not reserve paths for future operations. A directory or permission change after reset acceptance may surface only when the new model is built. See [Storage files](../data-processing-system-architecture/data-storage-format/files.md), [DECLARE](../query-language-construction/declare-command.md), and [Ad hoc queries](ad-hoc-queries.md).

## Invalid data, missing input, and NULL values

| Diagnostic or symptom | Execution response | Prevention |
| --- | --- | --- |
| `invalid numeric token ... read as NULL` | An invalid number in TEXTFILE becomes NULL. One invalid array element makes its entire descriptor field NULL. The warning identifies the file, record, field, and token, only for the first occurrence in that accessor. | Validate the complete token and type range before writing the source; check negative UINT, BYTE above 255, extra characters, `inf`, and `nan`, among others. Correct all invalid records, not just the first reported one. |
| `Read failure from declared source ... Returning null row.` | After a read failure other than an EILSEQ content error, the buffer forwards the record and NULL map returned by the accessor; it does not stop the entire execution for that reason. The warning occurs once per source. | Check earlier source diagnostics, the producer, and the storage device. Startup required an available source; later NULL values do not permit a missing file at startup. |
| `DEVICE ... no writer (end of file)`, `read failed ... due records are all-null` | A missing producer or device read error gives NULL in due records. Returning data is reported as `data resumed`. | Start the producer, check the connection, and set `TIMEOUT` or `sources.timeout_s` for the actual record delivery time. The accessor does not automatically open a new object substituted at the same path. |
| `writer left after ... bytes ... incomplete record dropped` | The producer closed the device partway through a record; that fragment is discarded. | Write complete binary records matching the schema and check producer errors and short writes. |
| `awaitRecords: poll failed ... no further wait in this slot` | There is no further device wait in this slot; their accessors determine data availability. | Check the system cause and device descriptors. Increasing the timeout does not repair a `poll` error. |

End of file with `--until-eof` is a normal termination at the first exhausted source. Without that option files loop; an empty looping text file gives a read error and NULL records. Waiting for an operator's startup tail can mean no emission rather than a failure. A NULL result, such as division by zero, is also not itself a process-stopping error. Distinguish it from a returned `EvalError`.

## Computation errors and internal state

`Operator ... not defined for ...`, `math functions require numeric operand`, `toLogicValue: ... not supported`, and `aggregation not supported for this field type` identify an operation unavailable for the operand types. If the error returns while executing a slot, `xretractor` stops the plan through its engine-error path. Check field types, function arguments, and rule conditions against [Field expressions and scalar functions](../query-language-construction/select-command/field-expressions-and-scalar-functions.md). The parser or compiler should reject most invalid constructions earlier; a repeatable execution-only failure should be reported with a minimal plan and input.

`internal record count mismatch`, a missing attached payload, an index beyond buffer capacity, an inconsistent execution mask, and `RDB_ASSERT` diagnostics indicate a violated internal condition. Do not guess a repair by changing storage bytes. Keep the version, plan, descriptors, input, and log; stop automatically repeating the failing run and report the defect. Not every internal check ends the process: `Engine invariant violated while handling command` can return `engine error: ...` to the client without terminating the server. Continued operation in that case does not confirm a correct state.

`getRow ... timeOffset beyond history` or `fetchForward ... record ... not available` concern a requested record that storage cannot provide; some such paths return NULL rather than an exception. Check retained history, retention, logical origins, and whether the source supplied the necessary data. Increase history resources only after confirming that capacity is actually the cause; see [Plan dimension limits](../query-compilation/plan-size-limits.md).

## Storage writes, metadata, rotation, and DUMP

| Diagnostic fragment | Scenario and response | Action |
| --- | --- | --- |
| `::write ... failed`, `made no progress`, `::pread ... failed`, `partial read`, a `stat`, `file_size`, or segment-open error | Storage is full, read-only, unavailable, or a file was truncated. A propagated storage I/O error ends `xretractor` with EIO. | Check the system cause, space and inodes, mounts, and permissions. Do not modify a running instance's files. Keep a copy before repairing a partial write. |
| `trailing bytes; truncating ...` | A POSIX/POSIXSHD accessor found an incomplete record or shadow entry and attempts to truncate the tail to a format boundary. `lseek`/`ftruncate` failures are reported separately. | Investigate earlier interrupted writes and device health. Truncation does not reconstruct the lost tail; prevent sudden power loss and concurrent file editing. |
| Failure to open or rewrite `.meta` / `.meta.shadow` | A corrupt or unavailable index may refuse opening, detach metadata persistence, or return I/O, depending on the operation. | Preserve data and indexes together; check format and permissions. Do not assume every metadata error stops the process or that every metadata-write failure propagates. |
| `Rotation counter file ...`, `Cannot reserve rotation number`, `Rotation counter ... NOT saved` | Invalid counter contents refuse the plan at preflight; unavailability or a late reservation error is an environment failure. | Restore a verified counter and access to its directory. Deleting the counter restarts numbering at 0 and can overwrite existing archives. |
| `saved, but directory fsync failed`, `Rotation of ...` failures | A reservation or archive operation lacks full durability confirmation. Not all these failures stop startup or the stream. `overwrote existing archive ... previous content is lost` reports actual loss of the previous archive. | Check files and the counter after stopping, device health, and earlier diagnostics; continued operation alone does not confirm successful archiving. |
| `dumpManager::createDumpFile: failed to remove/create`, seek failure, `write to ... failed after ... bytes` | A dump could not be created or written. A propagated DUMP failure ends execution as I/O with EIO, preserving the service plan. | Prepare the directory and space; inspect the named path. A partial write can leave the beginning of a record in the file; the operation is not rolled back. |
| `Stream ... grows without bound on disk` | A warning about unbounded growth; it does not itself end execution. | Choose `RETENTION capacity segment_count`, MEMORY storage, or a suitable substrate profile for the plan's purpose. Monitor capacity for metadata and dumps too. |

A successful data write does not establish a transaction with metadata or synchronize the entire result to durable storage. A plan preserved after EIO is not a checkpoint. After repair, verify the last complete records and how input will be processed again. See [Files](../data-processing-system-architecture/data-storage-format/files.md), [Rotation](../data-processing-system-architecture/data-storage-format/rotation.md), and [Alerting implementation](alerting-implementation.md).

## SYSTEM rules and real-time settings

`system() call failed`, `system() command exited with status: ...`, and `system() command did not terminate normally` concern the command launched by a `DO SYSTEM` rule. The engine logs the error and continues processing rules; it does not automatically retry the failed command. Check the command as the service account, its environment, paths, and dependencies. The child program's code is not the exit code of `xretractor`. A long synchronous command can delay a slot; move lengthy work into a separate process accepting short requests.

`mlockall failed`, `SCHED_FIFO failed`, unavailable RT policy, or CPU affinity failure mean weaker execution conditions, generally with continued operation. Check permissions and limits for locked memory and priorities, available CPUs, and host configuration. Choose a priority within the supported range; increasing it alone does not remove I/O cost or overload. Platforms lacking the relevant facility use an explicitly weaker path. Correct-value tests and exit code 0 do not prove deadlines were met; see [Query tree traversal algorithm](query-tree-traversal-algorithm.md) for scheduling and measurement.

## The bus and safe IPC opening

| Diagnostic | Cause and response | Action |
| --- | --- | --- |
| `xrdbbus: cannot access/create/map`, `stayed undersized`, `was never initialized`, `foreign or incompatible layout` | Access failure, a damaged segment, or an incompatible layout. Startup may fall back to operating without global name and resource protection; this is not a safe state for an arbitrary collection of instances. | Check the account, versions, and shared memory. Repair or remove the named segment only after stopping every instance mapping it. |
| `ENOTRECOVERABLE`, `Running WITHOUT name uniqueness`, bus mutex failure | The mutex or locking protocol prevents use of the registry. Reset can be refused before acceptance; a late activation failure has a different effect. | Keep the segment diagnostic. Do not remove it from under running processes: that would split the resource registry. |
| `process entry ... is unreadable ... treated as alive` | Owner liveness cannot be reliably determined, for example because of `hidepid` or `ProtectProc`; its claims are retained. | Check process visibility as the server account. Lack of access to `/proc` alone does not justify deleting resources. |
| `IPC object ... untrusted owner`, `mode ... required 0600`, `not a regular object with a single link`, `name no longer identifies ...`, untrusted directory | Owner, mode, type, or identity verification refused the object. A foreign command queue or response segment blocks startup; a foreign client queue blocks its subscription. | Run the client with the same effective UID as the server, including when using root. Check the directory and object provenance without broadening access to other accounts. |
| `IPC startup refused`, `IPC resources could not be created`, `Startup aborted: IPC resources unavailable.` | The server could not safely clean up its predecessor or create its IPC; startup failed. | Check the preceding cause: owner, permissions, name collision, capacity, and version compatibility. |
| `IPC communication thread stopped, server no longer accepts commands` | An exception ended the communication thread; commands can no longer be served, after readiness was announced, it does not invoke the startup-failure callback. Processing may continue without command handling. | Keep the cause and check the actual process state; restore the instance after resolving the problem. |

Live instances' objects are protected by locks and the bus. `xretractor --cleanup` handles abandoned resources within this mechanism's limits; it does not enumerate every client queue left after SIGKILL. See [Multiple instances and the bus](../data-processing-system-architecture/multiple-instances-and-bus.md) for the procedure and limitations.

## IPC capacity and oversized responses

| Diagnostic fragment | Cause and effect | Prevention |
| --- | --- | --- |
| `shared memory too small: fixed reservation needs ...` | Insufficient space for fixed instance objects; refusal before execution. | Check `xretractor -c --shmbudget plan.rql`, Linux `/dev/shm` capacity, and the container limit. Separate instance names do not increase capacity. |
| `response queue for stream ... needs ... shared memory has ... free` | There is insufficient space for a new subscription queue. The server first releases idle pool entries if no ready queue of the correct capacity exists. | Limit clients or deliberately reduce `ipc.queue_buffer_seconds` / `ipc.min_queue_elements`, allowing for the increased overflow risk. Increase shared-memory capacity if the workload requires it. |
| `serialized row is ... does not fit the ... response queue slot; subscribers ... receive no data` | The serialized row exceeds the 1024 B slot. Emission is skipped; the error occurs once per stream, while the server keeps processing the plan. | Subscribe to a narrower projection or reduce arrays and strings. Increasing queue element count does not increase one row's size. Consider artifact storage for the complete result. |
| `IPC response ... a response slot holds ... replaced with an error` | A command response exceeded 128 KiB; the client receives an error instead. This is a different limit from a subscription row slot. | Limit response/expanded-plan size; keep a reproducer if a valid plan exceeds the limit. |
| `all ... response slots are held by live clients` | All 16 command-response slots are occupied; the new response is dropped. Slots of confirmed dead clients can be reclaimed. | Limit concurrent requests, ensure clients receive responses and finish requests, and check stuck processes. |
| `command queue ... stayed full until the deadline`, `server not found` | The command could not enter the queue or a response did not arrive before the common deadline. `server not found` does not establish process absence. | Check server state and load, the IPC log, and client count. Increase `ipc.client_response_max_fails` only for a justified waiting time. |

The `--shmbudget` report is an estimate rather than a space reservation. Queue capacity depends on stream rate and buffering settings. Other instances and queues retained in the pool also consume space.

## Full, abandoned, and reused client queues

The server sends each record without waiting for space. A full queue or detected abandoned mutex immediately unregisters the subscription; the communication thread handles later release or pooling. A slow client, blocked output pipe, stopped receiver process, and a client killed suddenly can therefore produce a similar final symptom: no further records.

| Level and diagnostic fragment | Meaning and response | Recommended action |
| --- | --- | --- |
| ERROR `response queue of client ... abandoned by a process that died holding its lock` | An owner died inside the queue's critical section; its mutex cannot be recovered. The server disables this subscription and cleans up the queue. | Use normal client termination; investigate crashes or forced SIGKILL. A new subscription receives a functioning queue. |
| WARN `queue erased on timeout, procId=...` | The queue was sent for removal after unregistering the client; it failed pool eligibility or reuse failed. | Check the preceding cause and reception rate. `timeout` names this logging path; `broadcast` triggers it on a failed nonblocking send, not by measuring a record's age. |
| WARN `queue pooled on timeout, procId=...` | A queue from a confirmed absent process was moved into the pool; it may still need further draining. | This entry describes a handled disconnection. Memory retained by the pool is expected; repeated disconnections require investigating the client. |
| WARN `response queue '...' not drained for reuse: ...` | Receiving while draining threw an exception, such as an unrecoverable mutex error. The queue will not be reused; the server closes the mapping and attempts to remove its name. | Check the appended cause. Do not manually reconstruct queue counters; retry a needed subscription after investigating the failure. |
| WARN `response queue '...' not empty after receiving its capacity; not reused` | A receive budget equal to queue capacity was exhausted while the queue remained nonempty. The server abandons reuse and releases it. | Keep the log and version; check custom clients or external writes to the queue. A properly unregistered queue should receive no new records. |
| WARN `broadcastOutOfBusiness: end marker not sent ...`, `queue erased on out-of-business` | Shutdown or reset ends the epoch; the end-marker send is attempted once and can fail. Subscription cleanup continues. | A client should handle both an end marker and silence/timeout. After reset, check the new schema and subscribe again. |
| ERROR `command queue ... abandoned ... recreating it` | A client died holding the command queue mutex; the server attempts to recreate the queue. Requests in the old queue may be lost. | Check every command result and server state before retrying a plan-changing operation. |

The pool holds at most two entries per instance. For instance `alfa`, their names are `brcdbr.alfa.p0` and `brcdbr.alfa.p1`; an unnamed instance uses `brcdbrp0` and `brcdbrp1`. A queue is handed to the next client only after draining and with exactly the same capacity. Draining uses batches of up to 256 messages: the first under the client name, then one batch for the oldest unready entry on successive communication-loop turns. A live process, zombie, or uncertain process inspection prevents its queue from entering the pool. A new client receives none of its predecessor's retained records.

To prevent disconnections, receive data continuously and keep the client's output flowing. A larger buffer helps with short delays but does not resolve a sustained rate mismatch and consumes more memory. An unregistered subscription is not automatically resumed; another `xqry --select` starts live reception and does not replay the gap. Store results if complete history is required.

### Queue-pool rename refusal

Reuse preserves the object and mapping by changing its name. Controlled refusals have the form `IPC object '...': ... (owner UID ..., expected UID ...)`; if the owner cannot be determined, they use `owner UID unavailable`. A general operation error may omit UID information.

| ERROR fragment | Cause | Response and operator action |
| --- | --- | --- |
| `cannot inspect object for rename` | The source object could not be checked, for example because its entry disappeared or access was denied. | Reuse is abandoned; check the directory and external object removal. |
| `rename target already exists` | The destination name is occupied, including by an object belonging to a different UID. | The existing destination remains untouched; check its provenance and owner. |
| `cannot inspect rename target` | Destination inspection produced a result other than confirmed absence. | Check the system cause and access to the IPC directory. |
| `rename to '...' failed` | The system rejected the rename or the operation threw an exception. | Check the reported cause, permissions, and IPC filesystem state. |

When returning an abandoned queue to the pool, rename failure leads to ordinary release. When taking a queue from the pool, the server releases the failed entry and attempts to create a new queue; that creation can fail too. Refusing the rename operation itself preserves source and destination, but its caller can subsequently clean up its own object. A foreign-account leftover at a pool name does not by itself block server startup. Owner, single link, mode 0600, and trusted namespace are checked as for other IPC objects.

## xqry client errors and JSONL events

| Presentation-format verdict | Symbolic code | Typical cause and action |
| --- | --- | --- |
| `stream unknown to the server` | `ENOENT` | Wrong name, a different server, or a stream removed by reset; check `--server`, `--dir`, and the schema. |
| `server did not answer within the timeout` | `ETIMEDOUT` | No response; check the process, IPC, and load, not just files in `/dev/shm`. |
| `server did not create the client response queue` | `ENOSR` | `show` refusal, insufficient memory, IPC verification failure, or epoch closure. The cause from `error.response` is recorded in the client log. |
| `no data in stream` | `ENOMSG` | Reception produced no record; check the source, startup tail, emitted stream, and `timing.query_no_data_timeout_ms`. |
| `server has no plan loaded (idle); load one with --reset` | `ENOENT` | An idle instance; deliver a plan if it should process data. A successful inventory of an idle instance can itself exit with code 0. |
| `server is shutting down` | `ECANCELED` | The command coincided with shutdown; wait and check the new instance or plan. |
| `select loop failed in the client; reason in the client log` | `EINTR` | Receive/render exception; check the client log. Already printed records are a partial result. |

`response queue ... did not appear after ... attempts` distinguishes `budget exhausted` from `aborted by client`; the latter does not prove the server failed to create the queue. An `incompatible layout` response segment requires checking client/server versions and their resources. Resolve ambiguous routing with explicit `--server`; a query using streams from different instances does not create a distributed plan.

In `--jsonl`, errors are `error` events with `code` and `message`, and the error exit code is `1`. Codes include `server_no_response`, `stream_not_found`, `no_active_plan`, `server_stopping`, `client_queue_missing`, `disconnected`, `idle_timeout`, `protocol_error`, and `communication_error`. `idle_timeout` applies to the explicit `--idle-timeout` silence limit; `protocol_error` includes a record from an unexpected stream. An `end` event with reason `limit` or `server_stopped_or_reloaded` is a successful termination. API clients additionally have their own subprocess-start and protocol-decoding errors, described in the [Stream monitoring API](../appendices/stream-monitoring-api.md).

## Command, reset, and ad hoc import refusals

| Diagnostic or family | Scenario and response | Recommended action |
| --- | --- | --- |
| `IPC command rejected: INFO directive`, `missing or invalid db.id`, `IPC message dropped` | A custom client sent a malformed or disallowed message. The server discards it; these cases may produce no response. | Use a supported client and format; do not send INFO directives such as an `#include` line. `#` inside an RQL value has a different context. |
| `command processor failure: ...`, `command handler failure: ...` | A handled handler exception returns through `error.response`; the server can still accept commands. | Check the full cause on both client and server. After a timeout of a state-changing operation, check its effect before retrying. |
| `plan epoch ended while subscribing ... repeat the command` | Reset or shutdown closed the epoch before registration; the prepared queue is removed. | Wait for the swap, confirm the name and schema, and subscribe again. |
| `reset-begin/chunk/commit rejected`, `Rejected: ...` | Wrong chunk count/order, missing or incomplete transfer, oversized plan, too many transfers, or a reset already in progress. | Serialize plan changes; use `xqry --reset`. Restart an interrupted transfer from the beginning and wait when overloaded. |
| `AdHoc rejected: ...`, `DO SYSTEM` refusal, or resource collision | The command could not be attached safely; newly imported nodes and claims can be rolled back. | Remove the reported cause. Ad hoc always refuses `DO SYSTEM`; reset requires explicit `service.unrestricted` for it. Do not enable it merely to bypass an unexplained refusal. |
| `Plan reload failed ... falling back to idle mode` | Reparsing/compilation while installing an accepted plan failed; the old model has already been dismantled. | Check the active plan and deliver a corrected version. |
| `Plan is running but could NOT be persisted`, service-startup-file write failure | The new plan is running but could not be preserved for restart. | Repair access to the startup file and deliver the verified plan again; check its persisted contents before restarting. |

Reset `OK` means acceptance, not completion of all later opens or durable storage. A late model-construction error can terminate the process without restoring the old model. Likewise, ad hoc rollback is not a general transaction for every I/O effect; late accessor-open refusal handling does not cover the GENERIC profile. See [Ad hoc queries](ad-hoc-queries.md) and [Service and plan replacement](../appendices/command-line-options/xretractor.md#service-and-plan-replacement).

## xtrdb and embedded Python execution

`xtrdb` refuses editing when it detects a running instance. `cannot verify whether xretractor is running` means a lock-check error prevented safely confirming its absence. Stop instances and use the same lock-directory configuration; do not bypass protection with another path. For `open: ...`, check the descriptor and metadata. `record out of range` rejects an index before reading and preserves the payload, whereas a failed read of an admitted index sets `error`, and a listing can show `fetch error`. `write: ...`, `append: ...`, and an attempt to append to a read-only source also set payload status `error`; the terminal continues operating. Process code 0 after `quit` does not confirm earlier commands succeeded. See [xtrdb](../appendices/command-line-options/xtrdb.md).

An embedded `Engine` has no IPC or service clock. The binding maps core errors to `ConfigError`, `RQLSyntaxError`, `CompileError`, `CorruptDescriptor`, `IOError`, and `InternalError`. Returned `Errc::Eval` and `Errc::Logic` produce `InternalError`, which taints the entire module: guarded entry points refuse access until the interpreter restarts, while `close()` remains available. A `run()` failing with I/O prevents further plan progress until recompilation, preserving access to existing results. Argument errors can also produce `KeyError`, `IndexError`, `ValueError`, or `TypeError`. Check names, indexes, dimensions, and export types; NULL cannot become a valid integer value when exporting to NumPy.

`rdb::fatal()` and `RDB_ASSERT` take a separate path: by default they terminate the host through `abort`, including the Jupyter kernel; they do not become ordinary Python exceptions. Do not assume every failure can be handled with `try/except`. Use supported plans, serialize Engine access, and report invariant violations with a reproducer. See the full contract in [Python and Jupyter API](../appendices/python-jupyter-api.md).

## Implementation basis and tests

The description was checked against `master` revision `e0857dc8ba5387929c0e79d172cb8c45a669e3a3`. The following tests identify existing behavioral coverage; this table does not claim a new test run or verification on every platform.

| Area | Sources in the engine repository | Tests and scenarios |
| --- | --- | --- |
| Error classes and termination | `src/include/rdb/error.hpp`, `src/include/fatalError.hpp`, `src/retractor/lib/executorsm.cpp` | `ut_fatalError`, `it_fatal_exit_path-run`, `it_env_error_exit-run` |
| Source, descriptor, and storage checks | `planSource.cpp`, `src/rdb/lib/storage.cc`, `facc*` accessors | `ut_planSource`, `ut_rdb`, `ut_facctxtsrc`, `ut_sourceBuffer`, `it_storage_refusal-*`, `it_untileof_stop-missing-sources` |
| Devices and rules | `src/rdb/lib/faccbindev.cc`, `streamInstance.cpp`, `dumpManager.cpp` | `ut_faccbindev`, `ut_dumpManager`, `ut_expeval`, `it_issue42_rule-*` |
| Bus and IPC | `bus.cpp`, `ipcServer.cpp`, `ipcResponses.cpp`, `src/common/ipcSecurity.cpp` | `ut_bus`, `ut_ipcServer`, `ut_ipcResponses`, `ut_ipcSecurity`, `it_ipc_security-*` |
| Queue pooling and draining | `ipcServer.cpp`, `src/include/constants.hpp` | `IpcServerQueues.abandoned_queue_of_dead_client_is_reused_empty_by_next_subscriber`, `abandoned_queue_larger_than_one_batch_is_drained_over_several_turns`, `dead_mutex_between_drain_batches_releases_the_pool_entry`, `IpcSecurity.RenameMovesOwnQueueWithItsMappingAndRefusesUnsafeCases` |
| Commands and clients | `executorsmCommands.cpp`, `executorsmPlanReload.cpp`, `executorsmAdHoc.cpp`, `src/qry/`, `src/rdb/cmdStorage.cpp` | `it_subscribe_epoch_race-run`, `it_select_loop_failure-run`, `it_service_reset*`, `it_adhoc_register_rollback*`, `it_xtrdb_write_status-run`, `st_api_fake`, `st_api_real` |
| Embedded engine | `src/embed/`, `src/python/module.cpp` | `ut_embedEngine`, Python `test_error_classes.py`, `test_fatal_paths.py`, `test_storage.py` |

See [Integration tests](../appendices/integration-tests.md#requirements-in-code-and-test-traceability) for the coverage map and requirement identifiers. When reporting a failure, include the first error, its effect, and the smallest plan and data reproducing it; remove any material that may not be shared.
