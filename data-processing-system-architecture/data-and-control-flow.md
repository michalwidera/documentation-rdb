# Data and Control Flow

Data and control in RetractorDB give rise to several potential ways of using the system's components. Fig. 14 schematically shows the flow of data between RetractorDB's processes, Linux system processes, and the source data and results produced by each process.

The thickest lines represent the flow that is always present when regular time series are processed. After receiving an `.rql` file, xretractor compiles it, builds the query-plan tree, begins processing incoming data, and creates binary files containing artifacts. Without a file it can start idle and wait for a complete plan delivered by `xqry --reset`.

> **_NOTE:_** The functionality described here is covered by the test: `consistency`, described in the appendix [Integration Tests](../appendices/integration-tests.md).

To control the xretractor process once it has started, we use the xqry process. Through it, we can stop the xretractor process, retrieve statistics, or request access to current data.

The remaining arrows represent data flows that depend on the specific process being carried out with RetractorDB. Dashed arrows are typically intended for diagnostic purposes.

Each process on the diagram is additionally labeled with the number of continuous processes of that kind maintained in the system. The historical label "1" next to xretractor describes the one plan instance shown in the figure, not the current host-wide limit. Named instances can run concurrently; exactly one may act as the service in the default host namespace. The `xrdbbus` bus enforces separation of their resources. The xtrdb program does not maintain a continuous process: it reads data, returns a result, and exits, or runs interactively. The xqry process is labeled "N" because several clients can connect to each xretractor instance.

<figure><img src="../assets/przeplyw_danych_i_sterowania.svg" width="100%" alt=""><figcaption><p>Fig. 14. Data and control flow</p></figcaption></figure>

## Stopping xretractor

The xretractor process handles system signals and shuts down in a controlled manner upon receiving:

| Signal    | Command             | Meaning                                 |
| --------- | -------------------- | ---------------------------------------- |
| `SIGINT`  | Ctrl+C in a terminal  | interactive interrupt                    |
| `SIGTERM` | `kill <pid>`          | standard process termination              |
| `SIGHUP`  | `kill -HUP <pid>`     | termination on terminal close             |

All three signals produce the same effect: a graceful shutdown - the processing loop finishes the current cycle and stops. This allows xretractor, running as a service, to be shut down safely without risking corruption of artifact files.

### Stopping via xqry

Besides system signals, xretractor can be stopped programmatically - using the command:

```bash
xqry --server name --kill
```

#### How the shutdown proceeds step by step

**1. xqry sends a "kill" request**

The xqry process resolves an instance from `--server` or from the bus, builds an IPC message, and places it on that instance's command queue. The base name `RetractorQueryQueue` receives the named-instance suffix. The message contains the xqry process's identifier (PID) and the `kill` command.

**2. xretractor receives the command and sets the stop flag**

The selected instance's `IpcServer` communication thread continuously listens on its queue. After receiving a `kill` message, `executorsm::commandProcessor` sets the atomic `iLoopLimitCnt` counter to `stop_now` and wakes the execution loop. The same mechanism is used by the system-signal handler - regardless of the source, the effect is identical for that one instance.

**3. The main processing loop detects the flag and finishes the current cycle**

The main loop checks `iLoopLimitCnt` on every iteration. When it detects the value `stop_now`, it finishes the current cycle and exits the loop - without interrupting mid-computation. This ensures the integrity of the artifacts being written.

**4. xretractor notifies all connected clients (OOB broadcast)**

After exiting the loop, xretractor calls `IpcServer::broadcastOutOfBusiness()`. The IPC object walks the subscription registry, where the `show` command stored each client's PID and stream name. It sends every registered client a special `OUT_OF_BUSSINESS` message on its dedicated queue.

**5. Every xqry client receives the termination signal and exits**

Every xqry subscription has its own queue containing the server name and client PID. Upon receiving the `OUT_OF_BUSSINESS` message, xqry sets its internal `done` flag and shuts down in a controlled manner - regardless of how much data it had received up to that point.

**6. IPC resource cleanup**

Finally, xretractor removes its response segment, command queue, mutex, and client queues, then releases its lock file and bus slot. Other instances' resources remain untouched.

### Fatal errors and emergency cleanup

A fatal error during startup or in the communication thread follows the same final resource ownership policy but does not attempt to continue the processing cycle. The spdlog registry is flushed rather than destroyed before `atexit` handlers run. If the error originated in the communication thread itself, cleanup detaches that thread instead of attempting to join it from itself. It then removes IPC queues and shared memory and releases the service lock last.

The process exits with status 1. A later start therefore finds neither orphaned IPC nor a stale service lock, and the primary failure is not masked by a secondary `SIGSEGV` or `SIGABRT` during shutdown.

> **_NOTE:_** `fatal_exit_path` covers both startup failure and failure reported by the communication thread.

#### What happens with multiple xqry processes

RetractorDB is designed to work with multiple parallel clients. If, say, three xqry processes are running simultaneously, subscribed to different streams, and one of them calls `xqry --kill`:

- the selected xretractor processes the kill request **once**, regardless of which client sent it,
- `IpcServer::broadcastOutOfBusiness()` sends the `OUT_OF_BUSSINESS` message to **all** clients registered with that instance,
- each of the three xqry processes receives the termination signal and exits on its own,
- clients that hadn't subscribed to any stream (e.g. xqry invoked only with `--dir` or `--hello`) are not entered in the map and don't need to be notified - these commands exit immediately after providing their response.

Clients connected to other named instances do not receive the message and continue running.

It's worth noting that xqry also detects server inactivity: if no data arrives for 10 seconds, the client shuts itself down with a warning in the log. This is a safeguard in case xretractor crashes suddenly without being able to send the OOB message.
