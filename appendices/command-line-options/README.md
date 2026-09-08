# Command-Line Options

RetractorDB consists of three command-line tools, each playing a distinct role in the system's architecture:

| Tool           | Role                                                                 |
| -------------- | -------------------------------------------------------------------- |
| `xretractor`   | Processing process: compiles RQL and executes one independent plan |
| `xqry`         | Client: discovers or selects an instance and communicates through its IPC |
| `xtrdb`        | Inspection tool: analyzes binary artifacts and metadata          |

Each tool is described in its own subchapter.
