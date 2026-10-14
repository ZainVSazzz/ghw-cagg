-- 01_schema.sql
-- Hypertable for IDX 1-minute stock bars + synthetic data generation.
-- Run: psql -d ghw -f sql/01_schema.sql

DROP TABLE IF EXISTS market_ticks;

CREATE TABLE market_ticks (
    time    TIMESTAMPTZ NOT NULL,
    symbol  TEXT        NOT NULL,
    open    NUMERIC(12,2) NOT NULL,
    high    NUMERIC(12,2) NOT NULL,
    low     NUMERIC(12,2) NOT NULL,
    close   NUMERIC(12,2) NOT NULL,
    volume  BIGINT      NOT NULL
);

SELECT create_hypertable('market_ticks', 'time', chunk_time_interval => INTERVAL '7 days');

-- 10 IDX symbols, ~2 years of 1-minute bars (trading days only, 09:00-15:00 WIB).
-- Random-walk prices seeded per symbol for a realistic look.
INSERT INTO market_ticks (time, symbol, open, high, low, close, volume)
SELECT
    ts,
    sym,
    ROUND(px::numeric, 2)                       AS open,
    ROUND((px * (1 + 0.002 * rnd1))::numeric, 2)   AS high,
    ROUND((px * (1 - 0.002 * rnd2))::numeric, 2)   AS low,
    ROUND((px * (1 + 0.001 * (rnd3 - 0.5)))::numeric, 2) AS close,
    (500 + (rnd4 * 50000))::bigint     AS volume
FROM (
    SELECT
        ts,
        sym,
        5000 * (1 + 0.3 * SIN(EXTRACT(EPOCH FROM ts) / 86400 / 30)
                   + 0.0002 * (ROW_NUMBER() OVER (PARTITION BY sym ORDER BY ts) - 1)
                   + 0.02 * (random() - 0.5)) AS px,
        random() AS rnd1, random() AS rnd2, random() AS rnd3, random() AS rnd4
    FROM generate_series(
            TIMESTAMPTZ '2024-01-02 02:00:00+00',  -- 09:00 WIB
            TIMESTAMPTZ '2025-12-30 08:00:00+00',  -- 15:00 WIB
            INTERVAL '1 minute'
         ) AS ts
    CROSS JOIN (VALUES ('BBCA'),('BBRI'),('TLKM'),('ASII'),('BMRI'),
                       ('ADRO'),('INDF'),('KLBF'),('SMGR'),('UNTR')) AS s(sym)
    WHERE EXTRACT(ISODOW FROM ts) < 6  -- weekdays only
      AND ts::time BETWEEN '02:00' AND '08:00'
) t;

-- Stats for the README
SELECT count(*) AS total_rows,
       count(DISTINCT symbol) AS symbols,
       min(time)::date AS from_date,
       max(time)::date AS to_date,
       pg_size_pretty(pg_total_relation_size('market_ticks')) AS size
FROM market_ticks;
