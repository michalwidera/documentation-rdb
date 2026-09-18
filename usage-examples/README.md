# Usage Examples

This chapter presents short examples of using RetractorDB to solve concrete problems encountered when building monitoring systems.

Every example is complete - it includes a problem description, the RQL query design, how to run it, and how to interpret the results. The examples can be run on their own: the required data files and scripts are described step by step.

<div class="timeline">

- **[Signal filtering (FIR)](signal-filter-implementation.md)**

  This example demonstrates how to implement a **digital FIR filter** directly within an RQL query stream, without external DSP libraries. The topic is representative of a broad class of signal-processing problems: noise filtering, frequency-band separation, time-series smoothing.

  The example covers:

  - designing filter coefficients in GNU Octave (the Remez algorithm, the `remez()` method),
  - transferring the coefficients into a text file and loading them as a `DECLARE` stream,
  - implementing discrete convolution as a set of `SELECT` queries using the sliding-window `@` operator and expansion of the `_` symbol,
  - real-time visualization of the filtering process using `xqry` and `gnuplot`.

  The result is a working system that filters a pseudo-random signal (50 Hz) down to the 0–2 Hz band, observed live while xretractor is running.

- **[ECG Signal Analysis (MIT-BIH)](ecg-visualization-mit-bih.md)**

  This example demonstrates using RetractorDB to **process clinical ECG signals** from the public MIT-BIH Arrhythmia Database (PhysioNet). It's a complex use case combining several of the system's mechanisms: multi-channel input streams, a multi-stage FIR filtering pipeline, an adaptive detection threshold, and real-time visualization.

  The example covers:

  - data preparation: converting MIT-BIH recordings (WFDB format) into text files compatible with RetractorDB,
  - implementing the five-stage Pan-Tompkins algorithm in RQL: band-pass filter → differentiation → squaring → moving-window integration → threshold detection,
  - visualizing the ECG signal and the QRS-detection result in a gnuplot window (RTL mode - newest samples on the right),
  - interpreting the results: RR-interval readings, identifying arrhythmia episodes in MIT-BIH record 205.

  The result is a working QRS detector processing a two-channel ECG signal (MLII + V1) at 360 Hz, implemented entirely with RQL queries, with no specialized libraries.

- **[Candlestick Chart (OHLC)](candlestick-chart-ohlc.md)**

  This example demonstrates how to build **OHLC candles** (open, high, low, close) from a regular stream of samples and draw them live together with the samples they were built from. The same construction fits any signal viewed in intervals: quotes, sensor readings, load.

  The example covers:

  - smoothing noise with the record-window aggregate `AVG(... : 25)`,
  - a tumbling window with mirrored aggregation, `@(10,-10)`, which sets the candle boundaries and the order of its samples,
  - the `MAX` and `MIN` reducers in the `FROM` clause, and joining a candle with its samples into one record with the `+` operator,
  - visualization in the `xqry --gnuplot-ohlc` mode, started with the `ninja candlestick` target.

  The result is a chart of 25 candles of 10 samples, refreshed every 0.2 s, in which every candle stands exactly over the samples it was built from.

</div>
