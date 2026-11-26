# Spec: sopr_spent_output_profit_ratio (onchain_btc layer)

Status: **closed** (2026-11-26); variant to be confirmed with Sara. Built as
`int_btc_sopr` (refactor target). Rule:
`docs/indicator_rules/sopr_spent_output_profit_ratio.yaml`. Numbers below
come from read-only queries on `raw_market_metrics` on 2026-11-26. Layer: `docs/specs/onchain_btc_layer.md`.

## 1. Goal

SOPR = price at which coins are spent / price at which they were last moved.
Above 1, coins moving on-chain are sold at a profit; below 1, at a loss. A
short-term sentiment and capitulation gauge rather than a cycle-position
indicator (hence `relevance_level: 1`, `weight: 0.7`).

## 2. Source and formula

| | Original rule (Notion) | This spec |
|---|---|---|
| Source | Glassnode, `indicators/sopr` | **BGeometrics**, metric `btc_sopr` in `raw_market_metrics` |
| Formula | `sopr = value` | `sopr = value` (precomputed) |

- SOPR can't be derived from the raw layer (it needs spent-output data).
- `value` = payload field `sopr` (0 mismatches).
- **Variant to be confirmed with Sara:** plain SOPR, adjusted SOPR (aSOPR)
  or short-term holder SOPR (STH-SOPR).
- **History:** 1,455 rows, 2022-11-26 to 2026-11-19, 0 gaps, 0 duplicates,
  0 nulls, 0 values ≤ 0. Free-API window.
- **Range:** 0.883 (2023-03-30) to 1.178 (2025-07-04), median 1.0045; yearly
  mean 0.983-1.016. It oscillates around 1, as SOPR should.
- **Known isolated outlier: 0.8833 on 2023-03-30** (kept as is, no
  smoothing; decided 2026-11-26). Plausible but unverified. The days around
  it are 1.0017-1.0186 (1.0102 the day before, 1.0119 the day after), price
  flat (~28k), BGeometrics NUPL 0.297 (network in profit), exchange inflows
  normal (28.8k BTC). Most likely one large entity moving coins with a higher
  cost basis (e.g. a custodian or exchange reshuffle), not a market-wide
  capitulation. The value matches the payload, so it isn't a load error. Not
  checked against a second source. Effect: +1.0 BULLISH that day instead of
  −0.3 (with weight 0.7 / 3.8, it moves `layer_score` by ~0.24 for one day).
- **Latency: 7 days** (last value 2026-11-19 on 2026-11-26). **A limitation
  of the BGeometrics free plan**, not of our ingestion (confirmed by Sara,
  2026-11-26; closed). It would disappear with a paid plan or a different
  source; we are not paying for data.

## 3. Grain and keys

- One row per calendar day, key `event_time` (TIMESTAMP, 00:00 UTC), unique.
- Model: `int_btc_sopr` (view), columns `event_time`, `sopr`,
  `normalized_value`, `signal`, `btc_bias`, `message`; meta
  `indicator_id: sopr_spent_output_profit_ratio`, `layer: onchain_btc`,
  `relevance_level: 1`, `weight: 0.7`.
- Explicit NULL if `sopr` is NULL or ≤ 0. No forward-fill. No start date
  needed.

## 4. Bands

Raw daily value, `rolling_window: null` (decided). Bands
`[min_inclusive, max_exclusive)`, values from the original rule. Note the
asymmetry: the most bearish value is −0.6, the most bullish +1.0.

| sopr | normalized_value | signal |
|---|---|---|
| ≥ 1.05 | −0.6 | BEARISH |
| [1.00, 1.05) | −0.3 | BEARISH |
| [0.98, 1.00) | 0.0 | NEUTRAL |
| [0.90, 0.98) | 0.6 | BULLISH |
| < 0.90 | 1.0 | BULLISH |

Share of days per band (−0.6 / −0.3 / 0 / +0.6 / +1.0):

| Year | −0.6 | −0.3 | 0 | +0.6 | +1.0 |
|---|---|---|---|---|---|
| 2022 (from 11-26) | 0 % | 0 % | 75 % | 25 % | 0 % |
| 2023 | 0 % | 68 % | 30 % | 1 % | 0 % |
| 2024 | 6 % | 84 % | 10 % | 0 % | 0 % |
| 2025 | 1 % | 82 % | 16 % | 1 % | 0 % |
| 2026 | 0 % | 43 % | 51 % | 6 % | 0 % |

- In a bull market SOPR sits just above 1 for months, so the indicator reads
  −0.3 BEARISH most days of 2023-2025. That matches the rule's text
  (profit-taking = selling pressure), but it leans against the trend.
- The +1.0 band (< 0.90) was hit on 1 day in 4 years.

## 5. Freshness and expiry

- **Per-indicator expiry (decided):** SOPR's `max_age_days` in the layer mart
  is **10 days** (7 observed plus margin), not the 3 days of the daily block.
- It is read, like the other indicators, from a freshness block in
  `_sources.yml`: a **new block for BGeometrics** (identifier
  `raw_market_metrics`, filter `source = 'BGeometrics'`, `error_after`
  10 days), used as SOPR's `freshness_block` in `int_onchain_btc_signals`.
- The source-level freshness uses `ingested_at`, so a daily load with stale
  `event_time` passes it. The as-of in the mart uses `event_time`, so the
  expiry does catch a stalled series.
- **Why keep it despite the lag:** SOPR is a short-term oscillator, so a
  7-day lag reduces its usefulness more than for RHODL (slow-moving, where
  the lag barely matters). That is one reason it has the lowest weight in
  the layer (0.7).
- **Data age in the mart:** `btc_sopr_data_age_days` (days between the mart
  date and SOPR's latest available `event_time`) lets the agent weigh how
  stale the signal is (`docs/specs/onchain_btc_layer.md` §6).
- **Fallback (documented, not implemented):** if SOPR proves too stale to be
  useful, it is excluded from `layer_signal` and kept only as an individual
  indicator (`int_btc_sopr`). Coverage without SOPR: 3.1 / 3.8 = 82 %, above
  the 70 % minimum.

## 6. Tests (built)

- `unique` + `not_null` on `event_time`; `accepted_values` on `signal` and
  `btc_bias`; `sopr` > 0; `signal` NULL exactly when `sopr` is.
- Unit test `btc_sopr_band_edges_and_nulls`: 1.05 → −0.6, 1.00 → −0.3,
  0.98 → 0.0, 0.90 → +0.6, 0.89 → +1.0; 0 and NULL → NULL; another metric
  ignored.
- No historical reference test: no cycle bottom inside the window.

## 7. Open questions (for Sara)

- **Variant:** SOPR, aSOPR or STH-SOPR? Variant to be confirmed with Sara.
- **History:** any free way to get more than 4 years?
- Closed: the 7-day lag (BGeometrics free plan, §2).
- Closed: the 0.883 on 2023-03-30, documented as a known isolated outlier
  (§2).
