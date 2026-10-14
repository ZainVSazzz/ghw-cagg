-- 03_benchmark.sql
-- Dashboard query benchmark: raw ticks vs continuous aggregate.
-- Run: psql -d ghw -f sql/03_benchmark.sql

\timing on

\echo '=== Q1: daily OHLCV, all symbols, full 2 years — RAW ticks ==='
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
SELECT date_trunc('day', time) AS day, symbol,
       (array_agg(open ORDER BY time))[1] AS open,
       max(high) AS high, min(low) AS low,
       (array_agg(close ORDER BY time DESC))[1] AS close,
       sum(volume) AS volume
FROM market_ticks
GROUP BY 1, 2;

\echo '=== Q2: daily OHLCV, all symbols, full 2 years — CAGG ==='
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
SELECT bucket AS day, symbol, open, high, low, close, volume
FROM candles_1d;

\echo '=== Q3: hourly candles for one symbol, last 90 days — RAW ==='
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
SELECT date_trunc('hour', time) AS hr,
       (array_agg(open ORDER BY time))[1] AS open,
       max(high) AS high, min(low) AS low,
       (array_agg(close ORDER BY time DESC))[1] AS close,
       sum(volume) AS volume
FROM market_ticks
WHERE symbol = 'BBCA' AND time > now() - INTERVAL '90 days'
GROUP BY 1;

\echo '=== Q4: hourly candles for one symbol, last 90 days — CAGG ==='
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
SELECT bucket AS hr, open, high, low, close, volume
FROM candles_1h
WHERE symbol = 'BBCA' AND bucket > now() - INTERVAL '90 days';
