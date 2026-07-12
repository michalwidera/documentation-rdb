# Artifacts, Substrates, Ephemerides

Given that the system is designed for continuous operation, and that, theoretically, the results obtained without a data-retention process would fill up any storage medium, we introduce additional definitions related to the nature of the data being processed.

In presenting the description of Fig. 13, artifacts were mentioned. This is one of the terms that needs explaining.

> **✅ Note**
>
> Definition (Artifact): By artifacts we mean data processed in the system in the form of streams that are ultimately materialized as a durable result and effect of processing other data.


Continuous time series can be read from devices, then processed — reduced or resized in time and in dimension. But as a rule, certain data should be saved. Whether that data is later subject to retention is a secondary matter. Data that constitutes the result and expected output of the system, we call artifacts. Something we expect and materialize for the end user's needs.

> **✅ Note**
>
> Definition (Substrate): Substrates are intermediate objects. As a result of processing time series, data streams may arise that are ephemeral — needed only for and during processing.


Their size can be significant, considering how far back we go, for example when dumping historical monitoring data. However, their existence is irrelevant with respect to the system's desired output. We call such data streams substrates. They arise as a result of the system's operation; as a rule they do not appear explicitly in queries — but they result from the process of processing time series, and yet their results are necessary to accomplish the task.

> **✅ Note**
>
> Definition (Ephemeris): Ephemerides are objects on the basis of which we create source data streams — data that cannot be stored. As a rule, these are ephemeral, transient data.


For example, the system reads random numbers at a given rate, and it is precisely this data source that provides ephemeral data. It cannot be returned; storing it is, as a rule, pointless — it must be passed on for further processing in order to produce artifacts or substrates, and then discarded and replaced with new, current data.
