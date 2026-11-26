# Spec: rhodl_ratio_btc (onchain_btc layer)

Status: **closed with PROVISIONAL bands** (2026-11-26). Built as
`int_btc_rhodl_ratio` (refactor target). Rule:
`docs/indicator_rules/rhodl_ratio_btc.yaml`. Numbers below come from
read-only queries on `raw_market_metrics` and the refactor build on
2026-11-26. Layer: `docs/specs/onchain_btc_layer.md`.

## 1. Goal

A Bitcoin cycle indicator comparing the wealth held in young coins (1 week to
1 month) with the wealth held in older coins (1 to 2 years). High values mean
new money dominates (speculative excess, cycle tops); low values mean old
holders dominate (accumulation, cycle bottoms).

## 2. Source and formula

| | Original rule (Notion) | This spec |
|---|---|---|
| Source | Glassnode, `indicators/rhodl_ratio` | **BGeometrics** (free plan), metric `btc_rhodl_ratio` in `raw_market_metrics` |
| Formula | `value = RHODL_ratio` | `rhodl = value` (precomputed, no derivation) |

- Glassnode is paywalled and not in the raw layer; not used.
- RHODL can't be derived from the raw layer: it needs realized-cap HODL waves
  (coin-age bands), and only the precomputed ratio is loaded.
- The BGeometrics payload has two fields, `rhodlRatio` and `rhodl1m`;
  `value` holds `rhodlRatio` (0 mismatches).
- **History:** 1,461 rows, 2022-11-26 to 2026-11-25, 0 gaps, 0 duplicates,
  0 nulls. Free-API window: starts exactly 4 years before the load date.
- **Latency:** 1 day.

### 2.1 Cross-provider check (decided: accept BGeometrics)

Same cycle-level shape as LookIntoBitcoin's chart (read off the image, log
scale): end-2022 bottom ~200 (BGeometrics 202 on 2022-12-26), 2024 high ~13k
(13,730 on 2024-12-10), latest ~700 (722 on 2026-11-25).

Exact values (LookIntoBitcoin chart tooltip; Coinglass chart series; both
read-only, 2026-11-26):

| Date | BGeometrics | Coinglass | LookIntoBitcoin | Coinglass vs BGeometrics | LookIntoBitcoin vs Coinglass |
|---|---|---|---|---|---|
| 2026-07-21 | 835.71 | 765.75 | 723.79 | −8.4 % | −5.5 % |
| 2026-07-29 | 734.12 | 708.30 | 673.36 | −3.5 % | −4.9 % |
| 2026-09-02 | 1,003.25 | 931.60 | **512.64** | −7.1 % | **−45.0 %** |
| 2026-09-09 | 830.54 | 772.79 | 732.42 | −7.0 % | −5.2 % |
| 2026-11-25 | 721.83 | 663.42 | — | −8.1 % | — |

Decided (2026-11-26):
- **(a) Provider level differences of roughly 5-10 %.** Coinglass reads
  3.5-8.4 % below BGeometrics; LookIntoBitcoin ~5 % below Coinglass on
  normal days. Different methodology or inputs; none publishes enough to tell
  which.
- **(b) Thresholds calibrated on LookIntoBitcoin's chart zones and applied
  to the BGeometrics series: valid at cycle scale only.** Readings near a band
  edge are not reliable across providers.
- **(c) The 2026-09-02 dip is not replicated** by BGeometrics (1,003) or
  Coinglass (931.60; LookIntoBitcoin is the outlier, Coinglass +81.7 % above
  it): treated as a one-day artifact of LookIntoBitcoin. Not a date shift
  either (shifting BGeometrics ±21 days doesn't line the points up).
- **(d) Recalibrate the bands when more history exists.**
- **No smoothing** (`rolling_window: null`).

## 3. Grain and keys

- One row per calendar day, key `event_time` (TIMESTAMP, 00:00 UTC), unique.
- Model `int_btc_rhodl_ratio` (view), columns `event_time`, `rhodl`,
  `normalized_value`, `signal`, `btc_bias`, `message`; meta
  `indicator_id: rhodl_ratio_btc`, `layer: onchain_btc`,
  `relevance_level: 3`, `weight: 1.1`.
- Explicit NULL if `rhodl` is NULL or ≤ 0. No forward-fill. No start date.
- Expiry in the mart: 3 days (1-day lag + margin), from the daily freshness
  block, where `btc_rhodl_ratio` is listed (decided 2026-11-26). The
  BGeometrics block (10 days) also covers it.

## 4. Bands (PROVISIONAL)

The original thresholds (0.2 / 0.5 / 1.5 / 3.0) were on another scale (100 %
of days at −1.0). Replaced by bands on the raw scale. The outer bands come
from LookIntoBitcoin's chart zones (read off the image, not published
values). **The −0.6, 0.0 and +0.6 bands are ASSUMED.**

| rhodl | normalized_value | signal | Origin |
|---|---|---|---|
| ≥ 22,000 | −1.0 | BEARISH | LookIntoBitcoin red zone |
| [5,000, 22,000) | −0.6 | BEARISH | **ASSUMED** |
| [1,000, 5,000) | 0.0 | NEUTRAL | **ASSUMED** |
| [350, 1,000) | 0.6 | BULLISH | **ASSUMED** |
| < 350 | 1.0 | BULLISH | LookIntoBitcoin green zone |

Share of days per band (−1.0 / −0.6 / 0 / +0.6 / +1.0):

| Year | −1.0 | −0.6 | 0 | +0.6 | +1.0 |
|---|---|---|---|---|---|
| 2022 (from 11-26) | 0 % | 0 % | 0 % | 0 % | 100 % |
| 2023 | 0 % | 0 % | 21 % | 72 % | 7 % |
| 2024 | 0 % | 27 % | 73 % | 0 % | 0 % |
| 2025 | 0 % | 14 % | 86 % | 0 % | 0 % |
| 2026 | 0 % | 0 % | 66 % | 34 % | 0 % |

Reference readings: 2022-12-26 (202) → +1.0; 2024-12-10 (13,730, the 2024
high) → −0.6; 2026-11-25 (722) → +0.6. (Corrected: an earlier draft gave the
2024 high as 2024-12-29; that day is 5,984.)

### Known limitation: declining cycle tops

On LookIntoBitcoin the cycle peaks fall each cycle (approx. ~220k in 2013,
~90k in 2017, ~14k in 2021 and 2024). With a fixed −1.0 band from 22k,
**the 2021 and 2024 tops (~13-14k) fall in the −0.6 band, not −1.0**. The
−1.0 band hasn't fired since 2017. Same issue as MVRV-Z (its Q4). Not
recalibrated on two points; see (d).

## 5. Tests (built)

- `unique` + `not_null` on `event_time`; `accepted_values` on `signal` and
  `btc_bias`; `rhodl` > 0; `signal` NULL exactly when `rhodl` is.
- Unit test `btc_rhodl_ratio_band_edges_and_nulls`: 22000 → −1.0,
  5000 → −0.6, 1000 → 0.0, 350 → +0.6, 349.99 → +1.0; 0 and NULL → NULL;
  another metric ignored.
- `tests/assert_btc_rhodl_ratio_reference_points.sql` (warn): 2022-12-26 →
  +1.0 BULLISH; 2024-12-10 → −0.6 BEARISH.

## 6. Open items

- **History (for Sara):** any free way to get more than 4 years?
- Minor, not asked: which coin-age bands BGeometrics uses (`rhodlRatio` vs
  `rhodl1m`); one row whose payload couldn't be parsed for `d` in the QA
  (not investigated; the series has no gaps or duplicates).
- Exact LookIntoBitcoin zone levels, if ever published, would replace the
  values read off the image.
