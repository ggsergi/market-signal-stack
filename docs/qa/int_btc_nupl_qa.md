# QA: int_btc_nupl

Model under review: `models/intermediate/int_btc_nupl.sql` (view), with
`models/intermediate/int_btc_nupl.yml` and
`tests/assert_btc_nupl_reference_points.sql`.
Rule: `docs/indicator_rules/btc_nupl_cycle_regime.yaml`.
Spec: `docs/specs/btc_nupl_cycle_regime.md`.

The view is built in `market_signal_marts_refactor` (`--target refactor`).
All queries below are read-only and were run on 2026-11-11 against that view
and `raw_market_signals.raw_market_metrics`; they can be pasted as is into the
BigQuery console.

## 1. Review checklist

Formula and source
- [ ] `nupl = 1 - 1 / mvrv`, with `mvrv` = metric `btc_mvrv` (Coin Metrics
      `CapMVRVCur`) and nothing else.
- [ ] The derivation is right: MVRV = market cap / realized cap, so
      NUPL = (market cap − realized cap) / market cap = 1 − 1 / MVRV.
- [ ] The model reads `stg_market_metrics`, not the raw table directly.

NULLs
- [ ] `nupl`, `normalized_value`, `signal`, `btc_bias` and `message` are NULL
      before 2012-01-01.
- [ ] They are also NULL when `mvrv` is NULL or ≤ 0.
- [ ] `mvrv` itself is kept before 2012 (visibility only).
- [ ] No NULL signal from 2012-01-01 to the latest day (query Q4).

Bands
- [ ] Five bands, `[min_inclusive, max_exclusive)`, ordered from the top
      down: ≥ 0.70 → −1.0, [0.60, 0.70) → −0.6, [0.30, 0.60) → 0.0,
      [0.00, 0.30) → 0.6, < 0.00 → 1.0 (query Q2).
- [ ] `signal`, `btc_bias` and `message` use the same cut points as
      `normalized_value`.
- [ ] Messages match the rule word for word, including the rewritten
      [0.00, 0.30) one.

Tests
- [ ] `dbt build --target refactor --select int_btc_nupl`: 13/13 pass
      (1 unit test, 1 view, 11 data tests).
- [ ] The unit test covers each band edge with MVRV values whose NUPL is exact
      in floating point, plus the three NULL cases and a row of another metric.
- [ ] The reference-point test is at `warn` severity and its 8 points match
      `reference_points` in the rule.

Conventions
- [ ] View, in `models/intermediate/`, named `int_btc_nupl`.
- [ ] `meta`: `indicator_id: btc_nupl_cycle_regime`, `layer: onchain_btc`,
      `relevance_level: 2`, `weight: 0.9` (same as the rule).
- [ ] Code, comments and YAML in English; bot messages in Spanish.
- [ ] No contract or grants (intermediate models are internal).

Not covered here (open)
- [ ] `btc_mvrv` is not in the daily freshness filter of `_sources.yml` (P4,
      waiting for Sara).
- [ ] The model is not wired into a layer yet (`int_onchain_btc_signals`,
      `mart_onchain_btc`).

## 2. Verification queries

### Q1. Spot check: raw MVRV, NUPL by hand and NUPL from the view

```sql
SELECT
  DATE(SAFE_CAST(r.event_time AS TIMESTAMP)) AS day,
  r.value AS mvrv_raw,
  1 - 1 / SAFE_CAST(r.value AS FLOAT64) AS nupl_by_hand,
  v.nupl AS nupl_view,
  ABS((1 - 1 / SAFE_CAST(r.value AS FLOAT64)) - v.nupl) AS abs_diff,
  v.signal,
  v.normalized_value
FROM `<project>.raw_market_signals.raw_market_metrics` AS r
JOIN `<project>.market_signal_marts_refactor.int_btc_nupl` AS v
  ON v.event_time = SAFE_CAST(r.event_time AS TIMESTAMP)
WHERE r.metric = 'btc_mvrv'
  AND DATE(SAFE_CAST(r.event_time AS TIMESTAMP)) IN ('2021-03-13', '2026-11-10')
ORDER BY day
```

| day | mvrv_raw | nupl_by_hand | nupl_view | abs_diff | signal | normalized_value |
|---|---|---|---|---|---|---|
| 2021-03-13 | 3.78957634 | 0.7361182595941582 | 0.7361182595941582 | 0.0 | BEARISH | −1.0 |
| 2026-11-10 | 1.3666465515175559 | 0.268281913206032 | 0.268281913206032 | 0.0 | BULLISH | 0.6 |

Result: the view matches the hand calculation exactly on both days.

### Q2. Closest day on each side of every band edge

```sql
WITH v AS (
  SELECT DATE(event_time) AS day, nupl, normalized_value, signal
  FROM `<project>.market_signal_marts_refactor.int_btc_nupl`
  WHERE nupl IS NOT NULL
),
edges AS (SELECT edge FROM UNNEST([0.70, 0.60, 0.30, 0.00]) AS edge),
ranked AS (
  SELECT e.edge, IF(v.nupl >= e.edge, 'at_or_above', 'below') AS side, v.*,
    ROW_NUMBER() OVER (PARTITION BY CAST(e.edge AS STRING), v.nupl >= e.edge ORDER BY ABS(v.nupl - e.edge)) AS rn
  FROM edges AS e CROSS JOIN v
)
SELECT edge, side, day, ROUND(nupl, 6) AS nupl, normalized_value, signal
FROM ranked WHERE rn = 1
ORDER BY edge DESC, side
```

| edge | side | day | nupl | normalized_value | signal |
|---|---|---|---|---|---|
| 0.70 | at or above | 2021-03-29 | 0.700416 | −1.0 | BEARISH |
| 0.70 | below | 2017-06-04 | 0.699715 | −0.6 | BEARISH |
| 0.60 | at or above | 2013-05-17 | 0.600145 | −0.6 | BEARISH |
| 0.60 | below | 2017-10-03 | 0.599588 | 0.0 | NEUTRAL |
| 0.30 | at or above | 2014-08-26 | 0.300058 | 0.0 | NEUTRAL |
| 0.30 | below | 2026-05-20 | 0.299841 | 0.6 | BULLISH |
| 0.00 | at or above | 2014-12-31 | 0.000935 | 0.6 | BULLISH |
| 0.00 | below | 2014-12-24 | −0.000389 | 1.0 | BULLISH |

Result: every edge changes band on the right side.

### Q3. Rows per signal and year

```sql
SELECT
  EXTRACT(YEAR FROM event_time) AS year,
  COUNT(*) AS days,
  COUNTIF(signal = 'BULLISH') AS bullish,
  COUNTIF(signal = 'NEUTRAL') AS neutral,
  COUNTIF(signal = 'BEARISH') AS bearish,
  COUNTIF(signal IS NULL) AS no_signal
FROM `<project>.market_signal_marts_refactor.int_btc_nupl`
GROUP BY year
ORDER BY year
```

| year | days | bullish | neutral | bearish | no_signal |
|---|---|---|---|---|---|
| 2010 | 167 | 0 | 0 | 0 | 167 |
| 2011 | 365 | 0 | 0 | 0 | 365 |
| 2012 | 366 | 192 | 174 | 0 | 0 |
| 2013 | 365 | 2 | 200 | 163 | 0 |
| 2014 | 365 | 175 | 156 | 34 | 0 |
| 2015 | 365 | 349 | 16 | 0 | 0 |
| 2016 | 366 | 119 | 247 | 0 | 0 |
| 2017 | 365 | 0 | 142 | 223 | 0 |
| 2018 | 365 | 213 | 138 | 14 | 0 |
| 2019 | 365 | 182 | 182 | 1 | 0 |
| 2020 | 366 | 59 | 275 | 32 | 0 |
| 2021 | 365 | 0 | 193 | 172 | 0 |
| 2022 | 365 | 238 | 127 | 0 | 0 |
| 2023 | 365 | 217 | 148 | 0 | 0 |
| 2024 | 366 | 0 | 302 | 64 | 0 |
| 2025 | 365 | 0 | 364 | 1 | 0 |
| 2026 | 314 | 188 | 126 | 0 | 0 |

Result: the 532 rows without a signal are exactly 2010 and 2011. Tops (2013,
2017, 2021) lean BEARISH and bear markets (2015, 2018, 2022) lean BULLISH, as
expected. 2026 goes up to 2026-11-10 (Coin Metrics publishes one day late).

### Q4. No NULL signal from 2012-01-01, and no missing days

```sql
SELECT
  MIN(DATE(event_time)) AS first_day,
  MAX(DATE(event_time)) AS last_day,
  COUNT(*) AS rows_in_period,
  DATE_DIFF(MAX(DATE(event_time)), DATE '2012-01-01', DAY) + 1 AS expected_days,
  COUNTIF(signal IS NULL) AS null_signals
FROM `<project>.market_signal_marts_refactor.int_btc_nupl`
WHERE event_time >= TIMESTAMP '2012-01-01'
```

| first_day | last_day | rows_in_period | expected_days | null_signals |
|---|---|---|---|---|
| 2012-01-01 | 2026-11-10 | 5428 | 5428 | 0 |

Result: one row per day with no gaps, and no NULL signal in the period.

## 3. How to explain it in an interview

1. NUPL measures how much of Bitcoin's market value is unrealized profit: high
   values mean euphoria near cycle tops, negative values mean the average
   holder is at a loss, which has marked cycle bottoms.
2. Glassnode's ready-made series isn't in our raw layer, so I derived it from
   Coin Metrics' MVRV: since MVRV is market cap over realized cap, NUPL is
   exactly 1 − 1/MVRV, an algebraic identity rather than an approximation.
3. The signal is a fixed-threshold classification into five bands with
   inclusive lower bounds, and before 2012 it is explicitly NULL, because when
   almost every coin was mined at zero cost the ratio isn't a market reading.
4. I pinned the behaviour with tests at three levels: generic tests on keys,
   values and NULL rules; unit tests on every band edge with values that are
   exact in floating point; and warn-level checks on known historical tops and
   bottoms.
5. The unit test caught a real bug before anything was built — a CTE named
   like its own column, which BigQuery read as the whole row — which is
   exactly why I write the edge cases as tests rather than eyeballing output.
