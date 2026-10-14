#!/usr/bin/env python3
"""Benchmark: dashboard queries against raw ticks vs continuous aggregates.

Usage: python3 scripts/benchmark.py [--dsn "dbname=ghw user=postgres"]
Prints a markdown table comparing execution times.
"""
import argparse
import subprocess
import re
import sys

QUERIES = [
    ("Daily OHLCV, 10 symbols, 2 years",
     """SELECT date_trunc('day', time) AS day, symbol,
               (array_agg(open ORDER BY time))[1] AS open,
               max(high) AS high, min(low) AS low,
               (array_agg(close ORDER BY time DESC))[1] AS close,
               sum(volume) AS volume
        FROM market_ticks GROUP BY 1, 2""",
     """SELECT bucket AS day, symbol, open, high, low, close, volume
        FROM candles_1d"""),
    ("Hourly candles, 1 symbol, 90 days",
     """SELECT date_trunc('hour', time) AS hr,
               (array_agg(open ORDER BY time))[1] AS open,
               max(high) AS high, min(low) AS low,
               (array_agg(close ORDER BY time DESC))[1] AS close,
               sum(volume) AS volume
        FROM market_ticks WHERE symbol = 'BBCA'
          AND time > now() - INTERVAL '90 days' GROUP BY 1""",
     """SELECT bucket AS hr, open, high, low, close, volume
        FROM candles_1h
        WHERE symbol = 'BBCA' AND bucket > now() - INTERVAL '90 days'"""),
]


def explain_ms(dsn, sql):
    out = subprocess.run(
        ["psql", "-d", dsn, "-X", "-q", "-t", "-A",
         "-c", f"EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF) {sql}"],
        capture_output=True, text=True)
    m = re.search(r"Execution Time:\s+([\d.]+)\s*ms", out.stdout)
    if not m:
        print(out.stdout[-500:], file=sys.stderr)
        raise RuntimeError("could not parse EXPLAIN output")
    return float(m.group(1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", default="ghw")
    ap.add_argument("--runs", type=int, default=3)
    args = ap.parse_args()

    print("| Query | Raw (ms) | CAGG (ms) | Speedup |")
    print("|---|---|---|---|")
    for name, raw_q, cagg_q in QUERIES:
        raw = min(explain_ms(args.dsn, raw_q) for _ in range(args.runs))
        cagg = min(explain_ms(args.dsn, cagg_q) for _ in range(args.runs))
        print(f"| {name} | {raw:.1f} | {cagg:.2f} | {raw / cagg:.0f}x |")


if __name__ == "__main__":
    main()
