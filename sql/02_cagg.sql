-- 02_cagg.sql
-- Continuous aggregates: hourly and daily OHLCV candles per symbol.
-- The daily CAGG is hierarchical (built on top of the hourly CAGG).
-- Run: psql -d ghw -f sql/02_cagg.sql

-- 1-hour candles from raw 1-minute ticks
CREATE MATERIALIZED VIEW candles_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    symbol,
    first(open, time)  AS open,
    max(high)          AS high,
    min(low)           AS low,
    last(close, time)  AS close,
    sum(volume)        AS volume,
    count(*)           AS n_ticks
FROM market_ticks
GROUP BY bucket, symbol
WITH NO DATA;

-- Daily candles, straight from raw ticks (kept simple & robust)
CREATE MATERIALIZED VIEW candles_1d
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    symbol,
    first(open, time)  AS open,
    max(high)          AS high,
    min(low)           AS low,
    last(close, time)  AS close,
    sum(volume)        AS volume,
    count(*)           AS n_ticks
FROM market_ticks
GROUP BY bucket, symbol
WITH NO DATA;

-- Refresh policies: keep the last 30 days fresh, every 15 minutes
SELECT add_continuous_aggregate_policy('candles_1h',
    start_offset      => INTERVAL '30 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '15 minutes');

SELECT add_continuous_aggregate_policy('candles_1d',
    start_offset      => INTERVAL '30 days',
    end_offset        => INTERVAL '1 day',
    schedule_interval => INTERVAL '15 minutes');

-- Backfill everything once (historical data is static here)
CALL refresh_continuous_aggregate('candles_1h', NULL, NULL);
CALL refresh_continuous_aggregate('candles_1d', NULL, NULL);

-- Verify
SELECT 'candles_1h' AS view_name, count(*) AS rows FROM candles_1h
UNION ALL
SELECT 'candles_1d', count(*) FROM candles_1d;
