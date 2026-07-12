# Command-Line Options

RetractorDB consists of three command-line tools, each playing a distinct role in the system's architecture:

| Tool           | Role                                                                 |
| -------------- | -------------------------------------------------------------------- |
| `xretractor`   | The main processing process: compiles RQL queries and executes the plan |
| `xqry`         | Client: queries a running `xretractor` via shared memory        |
| `xtrdb`        | Inspection tool: analyzes binary artifacts and metadata          |

Each tool is described in its own subchapter.
