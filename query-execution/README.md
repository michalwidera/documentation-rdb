# Query Execution

The execution process is based on a continuous traversal of the query tree, and a sequential, hierarchical invocation of the procedures that build successive stream tuples and successive data schemas.

The description of the algorithm needs to start with the sequencing procedure. In a system executing queries with a variety of values defining the time period between successive created and arriving data, a way to determine successive intervals is needed.

Let's start by analyzing the following example. Suppose the system has two data streams. One arrives every second, the other every two seconds. The sequencing algorithm should propose a one-second time interval between invocations of the procedure intended for the first stream, and a two-second interval for the second stream. In practice, a one-second time grid will emerge - in which every one-second node is filled with the tuple-building procedure for the first stream, and, on that same time grid, the second stream attaches its procedures every second node.

The time grid determined during compilation is very important - it defines how often, and at what intervals, data streams will be processed, and which nodes will be covered by the generated stream-processing procedures.

Consider three streams with intervals of 1/3 s, 1/2 s and 2/3 s. A regular grid containing all their deadlines would have a step of 1/6 s: their intervals are respectively two, three and four times that step. A step of 1/5 s does not satisfy this condition. The `TimeLine` implementation does not visit every point of a common grid; it selects the nearest instant when at least one stream's next record is due.

The deadline generator retains intervals 1/3 and 1/2, because every deadline of the 2/3 stream is already a deadline of the 1/3 stream. After slot zero, successive instants are 1/3, 1/2, 2/3, 1, 4/3, 3/2, 5/3 and 2 seconds. At each instant the engine checks which of all the streams are due; coincident deadlines are handled in one slot. See [Query Tree Traversal Algorithm](query-tree-traversal-algorithm.md) for details.

Analyzing the discussion below may make clearer the comments, mentioned earlier in the chapter, generated for the swirly program showing the generated marble diagrams.
