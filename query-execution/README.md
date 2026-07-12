# Query Execution

The execution process is based on a continuous traversal of the query tree, and a sequential, hierarchical invocation of the procedures that build successive stream tuples and successive data schemas.

The description of the algorithm needs to start with the sequencing procedure. In a system executing queries with a variety of values defining the time period between successive created and arriving data, a way to determine successive intervals is needed.

Let's start by analyzing the following example. Suppose the system has two data streams. One arrives every second, the other every two seconds. The sequencing algorithm should propose a one-second time interval between invocations of the procedure intended for the first stream, and a two-second interval for the second stream. In practice, a one-second time grid will emerge — in which every one-second node is filled with the tuple-building procedure for the first stream, and, on that same time grid, the second stream attaches its procedures every second node.

The time grid determined during compilation is very important — it defines how often, and at what intervals, data streams will be processed, and which nodes will be covered by the generated stream-processing procedures.

Let's consider a more complex example. Suppose there are three data streams. The first arrives at a rate of ⅓, the second at ½, and the third at ⅔. Determining the grid and placing successive processing procedures requires a more elaborate solution. The value ⅔ can be simplified to ⅓, since there's a natural divisor between these values. There is, however, no natural divisor between ½ and ⅓. The grid value that gets determined is ⅕. This is the largest possible rational number that, if a grid is built on the rational-number axis, accommodates regular time series with arrival rates of ½ and ⅓.

All streams are overlaid onto the determined grid, and the set of minimal time gaps is determined for the queries with natural multipliers. In our case, the minimal set of time gaps for queries with multipliers (⅓, ½, ⅔) is the set (⅓, ½). The gaps ⅓ and ⅔ will share a time slot on the grid.

Analyzing the discussion below may make clearer the comments, mentioned earlier in the chapter, generated for the swirly program showing the generated marble diagrams.
