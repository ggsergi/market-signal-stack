# Spec: btc_mvrv_zscore (onchain_btc layer)

Status: **closed for build** (2026-11-26), in the `onchain_btc` layer
(`docs/specs/onchain_btc_layer.md`). Source: Coin Metrics. Formula and window
decided 2026-11-26 (§2). Built as `int_btc_mvrv_zscore` (refactor target).
Rule: `docs/indicator_rules/btc_mvrv_zscore.yaml`. **Still PENDING:** Q3 (4-7
band ASSUMED), Q4 (thresholds vs declining peaks), Q7 (relevance 3 / weight
1.1 TO CONFIRM), Q8 (P4 freshness), Q9 (output start date). Numbers from
read-only queries on `raw_market_metrics` and the refactor build on
2026-11-26.

## 1. Goal

A Bitcoin cycle indicator measuring how far market cap has moved away from
realized cap, in units of market cap's historical volatility. Very high values
have marked cycle tops; negative values, cycle bottoms.

## 2. Source and formula (decided)

```
realized_cap = market_cap / mvrv
mvrv_z       = (market_cap - realized_cap) / STDDEV_SAMP(market_cap)
               -- expanding window from the first available data point
```

- **Series:** `btc_market_cap` (Coin Metrics `CapMrktCurUSD`) and `btc_mvrv`
  (`CapMVRVCur`), both in `raw_market_metrics`, daily, from 2010-07-18, no
  gaps. Realized cap isn't in the raw layer; it is recovered as market cap /
  MVRV.
- **Standard definition** (Glassnode documentation, Coinglass, Look Into
  Bitcoin): standard deviation of **market cap**, cumulative from the first
  available data point. Look Into Bitcoin's Z recomputes exactly this way
  from its own series.
- **Sample standard deviation (`STDDEV_SAMP`)**, kept (sample vs population:
  5.091 vs 5.092 on 2021-04-13, no visible difference).
- **Expanding window from the first data point (2010-07-18)**, decided
  2026-11-26. No look-ahead: each day uses market caps up to and including
  that day.
- **Output start date 2012-01-01** (same as NUPL: before 2012 realized cap is
  not a market reading). Days before it are NULL but still enter the window.
- **The Notion formula (std of market cap − realized cap) is REJECTED.** It
  happened to give 7.45 on 2021-04-13 (close to the old "~7.5"), but 10.5 on
  2021-02-21, out of line with every external series.

### 2.1 Window start: 2012 vs first data point (decided)

Cycle maxima and minima, our two variants versus two external series (values
read from their chart series on 2026-11-26; Look Into Bitcoin's date labels
look shifted +1 day versus Coinglass, so cycle extremes are compared rather
than single dates):

| Point | Window 2012 | **Window first data (built)** | Look Into Bitcoin (from 2010-08-18) | Coinglass (from 2009) |
|---|---|---|---|---|
| 2013 max (2013-04-09) | 7.85 | **10.65** | 10.53 | 12.55 |
| 2017 max (2017-12-07) | 9.25 | **10.08** | 10.04 | 11.01 |
| 2021 max (2021-02-21) | 6.81 | **7.15** | 7.13 | 7.63 |
| 2021-04-13 | 5.09 | **5.38** | 4.99 | 5.75 |
| 2021-11-09 | 3.31 | **3.48** | — | 3.72 |
| 2015 min (2015-01-14) | −0.55 | **−0.60** | −0.60 | −0.68 |
| 2018 min (2018-12-15) | −0.46 | **−0.49** | −0.49 | −0.51 |
| 2020 min (2020-03-12) | −0.20 | **−0.20** | −0.20 | −0.26 |
| 2022 min (2022-11-09) | −0.35 | **−0.36** | −0.36 | −0.37 |
| Latest | 0.21 (2026-11-24) | **0.22** (2026-11-24) | 0.23 | 0.24 (2026-11-25) |

- The first-data-point window is closer to both external series at all three
  cycle tops, matches Look Into Bitcoin to ±0.12 at the tops and exactly at
  the four bottoms, and keeps all four bottoms negative. Applied.
- Coinglass starts in 2009 (an even earlier window and different inputs), so
  it reads higher, especially in 2013.
- **The 2021 top versus the +7 threshold:** window 2012 → 6.81, **−0.6
  BEARISH**; first data point → 7.15, **−1.0 BEARISH**. Look Into Bitcoin
  (7.13) and Coinglass (7.63) also put it above 7.

### 2.2 Why the old "~7.5 in April 2021" reference failed (corrected)

- It was **mislabeled**: ~7.5 is the **February 2021** peak (Look Into
  Bitcoin 7.13, Coinglass 7.63). April 2021 is ~5-5.75 in every series
  (2021-04-13: ours 5.38, Look Into Bitcoin 4.99, Coinglass 5.75).
- Earlier drafts blamed Coin Metrics' realized cap for the gap. **That was
  wrong, or at least not the main cause**: the window start matters more.
  With a 2012 start the 2013 top was 7.85 instead of ~10.5, and the 2021 top
  6.81 instead of ~7.1. Remaining differences with Coinglass (earlier window
  from 2009, other inputs) are of the order of 5-20 %.

### 2.3 Cross-check with BGeometrics

BGeometrics' precomputed `btc_mvrv_zscore` (2022-11-26 to 2026-11-19): measured
against the old 2012-window formula, correlation 1.000 and ~2.9 % higher on
average, consistent with BGeometrics using an earlier window. Not used as the
source (4 years of history, 7-day lag). Not re-measured against the new
window.

## 3. Grain, keys and NULLs

- **Grain:** one row per calendar day; key `event_time` (TIMESTAMP, 00:00
  UTC), unique. 5,974 rows, 2010-07-18 to 2026-11-24, 0 gaps.
- **Model:** `int_btc_mvrv_zscore` (view), meta `indicator_id:
  btc_mvrv_zscore`, `layer: onchain_btc`, `relevance_level: 3`, `weight: 1.1`
  (both TO CONFIRM).
- **Columns:** `event_time`, `market_cap`, `mvrv`, `realized_cap`,
  `market_cap_std`, `n_obs`, `mvrv_z`, `normalized_value`, `signal`,
  `btc_bias`, `message`.
- **Explicit NULL** in `mvrv_z` and everything derived from it:
  - before 2012-01-01 (output start date);
  - while the window has fewer than 365 observations: kept as a guard
    (decided), but **it no longer binds on real data**: `n_obs` is 533 on
    2012-01-01, so the first value is 2012-01-01 (Q9);
  - if `market_cap` or `mvrv` is NULL, `mvrv` ≤ 0, or the std is NULL / ≤ 0.
- **No forward-fill** in the indicator. Expiry in the mart: 3 days (daily
  freshness block).

## 4. Bands

`[min_inclusive, max_exclusive)`, as in every rule.

| mvrv_z | normalized_value | signal | Note |
|---|---|---|---|
| ≥ 7.0 | −1.0 | BEARISH | bubble |
| [4.0, 7.0) | −0.6 | BEARISH | **ASSUMED**: the source doesn't define 4–7 (Q3) |
| [2.0, 4.0) | 0.0 | NEUTRAL | |
| [0.0, 2.0) | 0.6 | BULLISH | |
| < 0.0 | 1.0 | BULLISH | |

Share of days per band by year (built model; −1.0 / −0.6 / 0 / +0.6 / +1.0):

| Year | −1.0 | −0.6 | 0 | +0.6 | +1.0 |
|---|---|---|---|---|---|
| 2012 | 0 % | 0 % | 1 % | 89 % | 11 % |
| 2013 | 7 % | 16 % | 36 % | 41 % | 0 % |
| 2014 | 0 % | 0 % | 10 % | 84 % | 5 % |
| 2015 | 0 % | 0 % | 0 % | 22 % | 78 % |
| 2016 | 0 % | 0 % | 4 % | 96 % | 0 % |
| 2017 | 4 % | 39 % | 47 % | 10 % | 0 % |
| 2018 | 0 % | 3 % | 9 % | 76 % | 12 % |
| 2019 | 0 % | 0 % | 6 % | 69 % | 25 % |
| 2020 | 0 % | 2 % | 14 % | 83 % | 2 % |
| 2021 | 1 % | 32 % | 38 % | 30 % | 0 % |
| 2022 | 0 % | 0 % | 0 % | 54 % | 46 % |
| 2023 | 0 % | 0 % | 0 % | 97 % | 3 % |
| 2024 | 0 % | 0 % | 48 % | 52 % | 0 % |
| 2025 | 0 % | 0 % | 65 % | 35 % | 0 % |
| 2026 | 0 % | 0 % | 0 % | 100 % | 0 % |

**Peaks still get lower each cycle** (10.65, 10.08, 7.15): the expanding
standard deviation keeps growing with market cap. The 2021 top now clears 7
(by 0.15), but a lower next top might not (Q4).

## 5. Tests (built)

On the model (`models/intermediate/int_btc_mvrv_zscore.yml`):
- `unique` + `not_null` on `event_time`; `accepted_values` on `signal` and
  `btc_bias`.
- `mvrv_z` NULL exactly when: before 2012-01-01, or `n_obs` < 365, or
  `market_cap` / `mvrv` missing, or `mvrv` ≤ 0, or `market_cap_std` NULL /
  ≤ 0.
- `signal` NULL exactly when `mvrv_z` is NULL.
- `realized_cap` > 0 and = `market_cap / mvrv` (relative tolerance 1e-6).
- `market_cap_std` > 0 and `mvrv_z` = formula (tolerance 1e-9).

Unit test `btc_mvrv_zscore_window_nulls_and_bands` (minimum lowered to 4 via
the var `btc_mvrv_z_min_obs`): a pre-2012 row enters the window (`n_obs`
counts it) but has a NULL Z; too few observations → NULL; zero std → NULL;
Z = 0.0 exactly → +0.6 (inclusive lower bound); Z ≈ 2.5 → NEUTRAL; Z < 0 →
+1.0; mvrv 0 / missing → NULL. **Not unit-tested:** the exact 2.0, 4.0 and
7.0 edges (a handful of rows can't reach them); real data has values within
0.03 on both sides of each (QA, `docs/qa/onchain_layer_qa.md`).

Historical reference points, warn severity
(`tests/assert_btc_mvrv_zscore_reference_points.sql`):

| Date | Event | Z | Expected |
|---|---|---|---|
| 2013-04-09 | 2013 cycle max | 10.65 | −1.0 BEARISH |
| 2015-01-14 | 2015 cycle min | −0.60 | +1.0 BULLISH |
| 2017-12-07 | 2017 cycle max | 10.08 | −1.0 BEARISH |
| 2018-12-15 | 2018 cycle min | −0.49 | +1.0 BULLISH |
| 2020-03-12 | COVID crash (2020 min) | −0.20 | +1.0 BULLISH |
| 2021-02-21 | 2021 cycle max | 7.15 | −1.0 BEARISH |
| 2022-11-09 | 2022 cycle min | −0.36 | +1.0 BULLISH |

## 6. Questions

Settled:
- **Q1. Minimum observations:** 365, kept as a guard; doesn't bind (see Q9).
- **Q2. The April 2021 reference:** mislabeled; it is the February 2021 peak
  (§2.2). Reference point 2021-02-21, −1.0.
- **Q5. Sample or population std:** sample (`STDDEV_SAMP`).
- **Q6. Redundancy with NUPL:** accepted as the "MVRV family" (~53 % of the
  layer's weight), to review once the agent uses the layer signal.
- **Formula:** std of market cap, window from the first data point (§2).

PENDING:
- **Q3. The 4–7 band** (−0.6) is ASSUMED: the source only says 2–4 is
  healthy and > 6–7 is a bubble.
- **Q4. Thresholds versus declining peaks** (10.65 → 10.08 → 7.15): keep
  fixed thresholds, or revisit?
- **Q7. Relevance and weight:** `relevance_level: 3`, `weight: 1.1`, TO
  CONFIRM.
- **Q8. Freshness (P4):** `btc_market_cap` and `btc_mvrv` are not in the
  daily freshness filter.
- **Q9. Output start date.** With the window from 2010, the 365-observation
  rule is satisfied by mid-2011; the output still starts on 2012-01-01 (the
  NUPL reason). Keep 2012-01-01, or publish from 2011-07-17 (first day with
  365 observations), as Look Into Bitcoin does from 2010?
