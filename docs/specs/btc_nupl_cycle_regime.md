# Spec: btc_nupl_cycle_regime (layer 3 pilot, on-chain)

Status: **approved**, with two data questions still open for Sara (P4, P9).
Rule: `docs/indicator_rules/btc_nupl_cycle_regime.yaml`. Model:
`int_btc_nupl`. Data checked in `raw_market_metrics` on 2026-11-11 (read-only
queries).

## 1. Goal

A Bitcoin cycle and market-psychology indicator based on NUPL (Net Unrealized
Profit/Loss): the share of the network's market value that is unrealized
profit. High values mean euphoria (risk of a top); negative values mean
unrealized losses (bottom zone).

## 2. Source and formula

| | Original rule | This spec |
|---|---|---|
| Source | Glassnode, series `unrealized_profit_loss` | **Coin Metrics**, metric `btc_mvrv` (`CapMVRVCur`) in `raw_market_metrics` |
| Formula | `nupl = unrealized_profit_loss` | **`nupl = 1 - 1 / btc_mvrv`** |

Derivation: Coin Metrics defines MVRV = market cap / realized cap. So
NUPL = (market cap − realized cap) / market cap = 1 − realized cap / market cap
= 1 − 1 / MVRV. It is an algebraic identity, so it needs neither
`btc_market_cap` nor `btc_supply`. LookIntoBitcoin defines NUPL the same way
(unrealized profit/loss divided by market cap).

Check against the data (it doesn't prove the identity, but confirms the
series behaves like NUPL):

| Period | NUPL min | NUPL max |
|---|---|---|
| 2013-12 top | 0.65 | 0.83 |
| 2015 bottom | −0.77 | 0.13 |
| 2017-12 top | 0.59 | 0.79 |
| 2018-12 bottom | −0.45 | 0.12 |
| 2020-03 COVID | −0.14 | 0.37 |
| 2021-03 top | 0.61 | 0.75 |
| 2021-11 top | 0.55 | 0.66 |
| 2022-11 bottom | −0.33 | 0.06 |
| Last year | 0.09 | 0.45 |

Latest value (2026-11-10): MVRV 1.367 → NUPL 0.268 → band +0.6 BULLISH.

This is NUPL on Coin Metrics' realized cap, not Glassnode's. The original
thresholds were designed on Glassnode; they are used as is, with no comparison
against Glassnode (decision P2).

## 3. Grain and keys

- **One row per calendar day** (Coin Metrics publishes 7 days a week). Full
  series from 2010-07-18 to 2026-11-10: 5,960 rows, 5,960 dates, 0 gaps,
  0 nulls, 0 values ≤ 0, all at 00:00 UTC.
- **Key:** `event_time` (TIMESTAMP, 00:00 UTC), unique.
- **Latency:** Coin Metrics publishes one day late (the 2026-11-10 value
  loaded on 2026-11-11).
- **Model:** `int_btc_nupl` (view in `models/intermediate/`), with
  `meta.indicator_id: btc_nupl_cycle_regime`, `meta.layer: onchain_btc`,
  `meta.relevance_level: 2`, `meta.weight: 0.9`.
- **Columns** (same pattern as the other `int_*` models with a message):

| Column | Type | Description |
|---|---|---|
| `event_time` | TIMESTAMP | day |
| `mvrv` | FLOAT64 | `btc_mvrv` as is (kept before the start date, for visibility) |
| `nupl` | FLOAT64 | `1 - 1 / mvrv` |
| `normalized_value` | FLOAT64 | −1.0 / −0.6 / 0.0 / 0.6 / 1.0 |
| `signal` | STRING | BULLISH / NEUTRAL / BEARISH |
| `btc_bias` | STRING | positive / neutral / negative |
| `message` | STRING | bot text from the rule (Spanish) |

## 4. Bands

The original rule's bands, with the project convention `[min_inclusive,
max_exclusive)`. MVRV equivalent (MVRV = 1 / (1 − NUPL)), to read them next to
other indicators built on the same input:

| NUPL | MVRV | normalized_value | signal |
|---|---|---|---|
| ≥ 0.70 | ≥ 3.33 | −1.0 | BEARISH |
| [0.60, 0.70) | [2.50, 3.33) | −0.6 | BEARISH |
| [0.30, 0.60) | [1.43, 2.50) | 0.0 | NEUTRAL |
| [0.00, 0.30) | [1.00, 1.43) | 0.6 | BULLISH |
| < 0.00 | < 1.00 | 1.0 | BULLISH |

The message for [0.00, 0.30) is rewritten without the "recovery" direction,
because the band is also reached on the way down (decision P11).

Share of days per band (−1.0 / −0.6 / 0 / +0.6 / +1.0):

| Year | −1.0 | −0.6 | 0 | +0.6 | +1.0 |
|---|---|---|---|---|---|
| 2017 | 9 % | 52 % | 39 % | 0 % | 0 % |
| 2021 | 13 % | 35 % | 53 % | 0 % | 0 % |
| 2022 | 0 % | 0 % | 35 % | 19 % | 46 % |
| 2024 | 0 % | 17 % | 83 % | 0 % | 0 % |
| 2025 | 0 % | 0 % | 100 % | 0 % | 0 % |
| 2026 | 0 % | 0 % | 40 % | 60 % | 0 % |

## 5. NULLs and window

- **No window:** a fixed threshold on the day's value, with no history needed.
  `rolling_window: null` (decision P3).
- **Explicit NULL** (`nupl`, `normalized_value`, `signal`, `btc_bias`,
  `message`):
  - **before 2012-01-01** (decision P1). In 2010-2011 the derived NUPL is not a
    market reading: almost every coin was mined at a cost of ~0 before there
    was a market, so realized cap is tiny and MVRV reaches 146 (NUPL 0.99).
    82 % of 2010's days would read "extreme euphoria", and in 2011-10 NUPL
    drops to −1.59. From 2012 on it behaves like a cycle indicator;
  - if `mvrv` is NULL or ≤ 0 (does not happen today; a guard against the
    division).
- **No forward-fill** in the indicator; carry-forward with expiry belongs to
  the layer mart, as in the other layers.
- **Freshness:** `btc_mvrv` is not in the daily filter in `_sources.yml` (the
  list is manual), so nothing warns today if it stops loading (P4, open).

## 6. Tests

On the model (`models/intermediate/int_btc_nupl.yml`):
- `unique` + `not_null` on `event_time`.
- `accepted_values` on `signal` and `btc_bias`.
- `nupl` is NULL exactly when the row is before 2012-01-01 or `mvrv` is NULL
  or ≤ 0, and `signal` is NULL exactly when `nupl` is.
- `nupl < 1`: with MVRV > 0, NUPL is always below 1.
- `ABS(nupl - (1 - 1 / mvrv)) < 1e-9`: pins the formula against future edits.

Unit tests (dbt `unit_tests`, mocked `stg_market_metrics` rows), to pin the
band edges with MVRV values whose NUPL is exact in floating point:
- MVRV 4.0 → NUPL 0.75 → −1.0 BEARISH.
- MVRV 2.5 → NUPL 0.60 exactly → −0.6 (lower bound inclusive).
- MVRV 2.0 → NUPL 0.50 → 0.0 NEUTRAL.
- MVRV 1.0 → NUPL 0.00 exactly → +0.6 BULLISH (lower bound inclusive).
- MVRV 0.8 → NUPL −0.25 → +1.0 BULLISH.
- A row before 2012-01-01, MVRV 0 and MVRV NULL → everything NULL.

Historical reference points (decision P7): a singular test at **warn**
severity checks the signal on 8 cycle tops and bottoms listed in
`reference_points` in the rule. Coin Metrics revises its series, so a warning
means "review", not necessarily an error.

## 7. Layer composition (decision P8)

> Updated 2026-11-26: the layer now has NUPL, MVRV-Z, SOPR and RHODL;
> Realized Price stays out. Current composition in
> `docs/specs/onchain_btc_layer.md`. The bullets below are the original
> decision.

- **Layer:** `onchain_btc`, mart `mart_onchain_btc` (decision P5). Avoids the
  clash with the planned final mart `mart_btc_cycle_signal`.
- **Indicators in the layer for now: NUPL only.**
- **Realized Price is out:** with Coin Metrics' price its distance is exactly
  MVRV − 1, and its rule disagrees with NUPL on the same input: a
  **different signal** (`SIGN(rp) != SIGN(nupl)`, NEUTRAL against BULLISH or
  BEARISH included) on 60.3 % of days in 2012-2023 and 80.6 % in
  2024-2026-11-24; a **strictly opposite sign** (`SIGN(rp) * SIGN(nupl) < 0`)
  on only 9.8 % and 5.9 %. BEARISH as soon as MVRV ≥ 1.3. (Corrected
  2026-11-26: this line used to say "opposite sign on 60 % / 82 %"; both
  definitions in `docs/specs/btc_realized_price.md` §4.)
- **MVRV Z-Score is a candidate, undecided.** It also derives from MVRV and
  market cap; LookIntoBitcoin doesn't give the formula, so the
  standard-deviation basis (market cap, or market cap − realized cap) and the
  window are still to be settled.
- **RHODL and SOPR** can't be derived from the raw layer (they need coin-age
  and spent-output data).
- Integration into the layer (`int_onchain_btc_signals`, `mart_onchain_btc`,
  `layer_signal`) is a separate step, not part of this spec.

## 8. Questions

Resolved:
- **P1.** NULL before 2012-01-01.
- **P2.** No comparison with Glassnode; Coin Metrics-derived NUPL is used.
- **P3.** `rolling_window: null`.
- **P5.** Layer `onchain_btc`, mart `mart_onchain_btc`.
- **P6.** Model `int_btc_nupl` (short name, like `int_nasdaq_tech_risk`).
- **P7.** Historical reference tests, yes, at warn severity.
- **P8.** NUPL only in the layer for now; Realized Price out; MVRV Z-Score a
  candidate, undecided.
- **P10.** `relevance_level: 2`, `weight: 0.9`.
- **P11.** The [0.00, 0.30) message is rewritten without a direction.

Open (for Sara):
- **P4. Freshness of the on-chain series.** Add `btc_mvrv` (and
  `btc_market_cap` / `btc_supply` if they are used) to the daily filter?
- **P9. `btc_price` backfill.** There is only data since 2025-09-26, even
  though ingestion declares a backfill from 2014-09-17. It doesn't affect
  NUPL.
