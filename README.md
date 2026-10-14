# IDX Market Pulse — Dashboards Accelerated with Continuous Aggregates

Submission for **MLH Global Hack Week: Open Source** — challenge
*"Accelerate Dashboards with Continuous Aggregates"*.

## The problem

A stock-market dashboard that renders 2 years of daily candles for 10 symbols
has to scan **1.88M raw 1-minute ticks** and aggregate them on every page load:

```sql
SELECT date_trunc('day', time) AS day, symbol, ...
FROM market_ticks            -- 1,880,810 rows
GROUP BY 1, 2;               -- ~5.3 seconds per load
```

## The fix

Two TimescaleDB **continuous aggregates** pre-compute the candles in the
background, so the dashboard reads a tiny pre-aggregated table instead:

| CAGG | Bucket | Rows | Refresh policy |
|---|---|---|---|
| `candles_1h` | 1 hour | 36,470 | last 30 days, every 15 min |
| `candles_1d` | 1 day | 5,210 | last 30 days, every 15 min |

```sql
CREATE MATERIALIZED VIEW candles_1d
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS bucket, symbol,
       first(open, time) AS open, max(high) AS high,
       min(low) AS low, last(close, time) AS close,
       sum(volume) AS volume, count(*) AS n_ticks
FROM market_ticks
GROUP BY bucket, symbol
WITH NO DATA;

SELECT add_continuous_aggregate_policy('candles_1d',
    start_offset => INTERVAL '30 days',
    end_offset   => INTERVAL '1 day',
    schedule_interval => INTERVAL '15 minutes');
```

## Results (measured with `EXPLAIN ANALYZE`, best of 3)

| Query | Raw (ms) | CAGG (ms) | Speedup |
|---|---|---|---|
| Daily OHLCV, 10 symbols, 2 years | 5346.0 | 1.09 | 4900x |
| Hourly candles, 1 symbol, 90 days | 0.2 | 0.02 | 7x |

Correctness verified: CAGG output matches raw aggregation exactly
(spot-checked per-symbol per-day high/volume).

## Try it

```bash
# 1. TimescaleDB running locally (or Tiger Cloud)
createdb ghw
psql -d ghw -c "CREATE EXTENSION timescaledb;"

# 2. Load schema + ~1.9M rows of synthetic IDX 1-minute bars
psql -d ghw -f sql/01_schema.sql

# 3. Create the continuous aggregates + refresh policies
psql -d ghw -f sql/02_cagg.sql

# 4. Run the benchmark
python3 scripts/benchmark.py --dsn ghw
```

## Files

- `sql/01_schema.sql` — hypertable `market_ticks` + synthetic data (10 IDX symbols, 2024–2025)
- `sql/02_cagg.sql` — `candles_1h` / `candles_1d` continuous aggregates + policies + backfill
- `sql/03_benchmark.sql` — raw-vs-CAGG `EXPLAIN ANALYZE` queries
- `scripts/benchmark.py` — prints the markdown comparison table above

## Why this matters beyond the demo

This mirrors a real production pattern: pre-computed summary tables fed by a
scheduled job (the MySQL-world equivalent of a CAGG). The demo uses synthetic
IDX data, but the same SQL shapes drop straight onto real market-data
pipelines — the dashboard query never touches raw ticks again.
