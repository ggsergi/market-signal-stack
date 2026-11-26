# QA: onchain_btc layer

> **Status — Independent QA by Claude Code: done (2026-11-26). Human QA by
> Sergi: PENDING (week of 2026-11-30).** Pending items: README, "Pending next
> week".

Models under review: `int_btc_nupl`, `int_btc_mvrv_zscore`, `int_btc_sopr`,
`int_btc_rhodl_ratio`, `int_onchain_btc_signals`, `mart_onchain_btc`, built in
`market_signal_marts_refactor` (`--target refactor`) on 2026-11-26, after:
- RHODL expiry moved to the daily freshness block (3 days);
- MVRV-Z window moved to the first available data point (2010-07-18);
- the `sara_marts_reader()` grant safeguard.

Method: independent reviewer. Recomputed from `raw_market_signals.raw_market_metrics`
with SQL written for this QA (no model SQL reused): the MVRV-Z standard
deviation via cumulative sums (sum of squares) instead of `STDDEV_SAMP`, bands
re-typed from the YAML rules, and the mart's as-of / expiry / coverage logic
rebuilt from the `int_` models. All queries are read-only SELECTs.

Rules: `docs/indicator_rules/{btc_nupl_cycle_regime, btc_mvrv_zscore,
sopr_spent_output_profit_ratio, rhodl_ratio_btc}.yaml`, layer
`docs/layer_rules/onchain_btc.yaml`. Specs in `docs/specs/`.

## Summary

| # | Check | Result |
|---|---|---|
| 1 | Grain, uniqueness, continuity | PASS |
| 2 | Independent recomputation from raw | PASS |
| 3 | Thresholds vs YAML (inclusive / exclusive) | PASS; 1 limit not testable on real data |
| 4 | Coverage and weights | PASS; "one stale indicator" NOT CHECKED on real data (none exists) |
| 5 | Explicit-NULL pattern | PASS |
| 6 | data_age and per-indicator expiry | PASS |
| 7 | Last row decomposition | PASS |
| 8 | Access (Sara's principal on the refactor marts) | PASS |

dbt tests in the same build: 58 tests, 58 PASS (including
`assert_per_metric_freshness` with the daily and BGeometrics blocks, and the
four unit tests).

## 1. Grain, uniqueness, continuity: PASS

| Model | Rows | Distinct dates | Duplicates | Not at 00:00 | Range | Missing dates |
|---|---|---|---|---|---|---|
| int_btc_nupl | 5,974 | 5,974 | 0 | 0 | 2010-07-18 to 2026-11-24 | 0 |
| int_btc_mvrv_zscore | 5,974 | 5,974 | 0 | 0 | 2010-07-18 to 2026-11-24 | 0 |
| int_btc_sopr | 1,455 | 1,455 | 0 | 0 | 2022-11-26 to 2026-11-19 | 0 |
| int_btc_rhodl_ratio | 1,461 | 1,461 | 0 | 0 | 2022-11-26 to 2026-11-25 | 0 |
| mart_onchain_btc | 5,443 | 5,443 | 0 | — | 2012-01-01 to 2026-11-25 | 0 |

- Raw rows equal model rows for every series (`btc_mvrv` 5,974 = NUPL;
  `btc_market_cap` ∪ `btc_mvrv` 5,974 dates = MVRV-Z; `btc_sopr` 1,455;
  `btc_rhodl_ratio` 1,461), and `int_onchain_btc_signals` carries the same
  counts per indicator: no row is dropped.
- The mart starts on the first day with any signal (NUPL, 2012-01-01) and ends
  on the latest observation of any indicator (RHODL, 2026-11-25).

## 2. Independent recomputation from raw: PASS

Over **all dates** (not only samples):

| Indicator | Max abs difference vs model | Band mismatches |
|---|---|---|
| NUPL = 1 − 1/MVRV | 0 (12 decimals) | 0 |
| MVRV-Z (cumulative-sum std, window from 2010-07-18) | 0 (9 decimals) | 0 |
| SOPR (passthrough) | 0 | 0 |
| RHODL (passthrough) | 0 | 0 |

Spot values (independent recomputation; normalized value in brackets):

| Date | NUPL | MVRV-Z | SOPR | RHODL |
|---|---|---|---|---|
| 2013-04-09 | 0.8227 (−1.0) | 10.652 (−1.0) | — | — |
| 2015-01-14 | −0.7744 (+1.0) | −0.598 (+1.0) | — | — |
| 2017-12-07 | 0.7880 (−1.0) | 10.084 (−1.0) | — | — |
| 2021-02-21 | 0.7474 (−1.0) | 7.150 (−1.0) | — | — |
| 2022-11-25 | −0.2255 (+1.0) | −0.261 (+1.0) | — | — |
| 2022-11-26 | −0.2304 (+1.0) | −0.266 (+1.0) | 0.9872 (0.0) | 290.07 (+1.0) |
| 2023-03-30 | 0.2960 (+0.6) | 0.586 (+0.6) | 0.8833 (+1.0) | 789.18 (+0.6) |
| 2024-12-10 | 0.6007 (−0.6) | 2.966 (0.0) | 1.0363 (−0.3) | 13,730.39 (−0.6) |
| 2026-02-12 | 0.1706 (+0.6) | 0.381 (+0.6) | 0.9792 (+0.6) | 1,582.47 (0.0) |
| 2026-11-19 | 0.1370 (+0.6) | 0.274 (+0.6) | 0.9839 (0.0) | 885.75 (+0.6) |
| 2026-11-24 | 0.1119 (+0.6) | 0.217 (+0.6) | — | 728.61 (+0.6) |
| 2026-11-25 | — | — | — | 721.83 (+0.6) |

## 3. Thresholds vs YAML: PASS

Closest real values on each side of every limit, with the model's band:

| Indicator | Limit | Closest at/above (band) | Closest below (band) |
|---|---|---|---|
| NUPL | 0.70 | 0.70042, 2021-03-29 (−1.0) | 0.69971, 2017-06-04 (−0.6) |
| NUPL | 0.60 | 0.60015, 2013-05-17 (−0.6) | 0.59959, 2017-10-03 (0.0) |
| NUPL | 0.30 | 0.30006, 2014-08-26 (0.0) | 0.29984, 2026-05-20 (+0.6) |
| NUPL | 0.00 | 0.00093, 2014-12-31 (+0.6) | −0.00039, 2014-12-24 (+1.0) |
| MVRV-Z | 7.0 | 7.0307, 2013-03-27 (−1.0) | 6.9703, 2021-02-20 (−0.6) |
| MVRV-Z | 4.0 | 4.0011, 2017-05-18 (−0.6) | 3.9859, 2017-06-28 (0.0) |
| MVRV-Z | 2.0 | 2.0001, 2024-10-28 (0.0) | 1.9985, 2024-07-23 (+0.6) |
| MVRV-Z | 0.0 | 0.0013, 2014-12-31 (+0.6) | −0.0005, 2014-12-24 (+1.0) |
| SOPR | 1.05 | **1.05 exactly**, 2024-10-11 (−0.6) | 1.0495, 2025-01-23 (−0.3) |
| SOPR | 1.00 | **1.00 exactly**, 2024-08-29 (−0.3) | 0.9999, 2023-03-12 (0.0) |
| SOPR | 0.98 | **0.98 exactly**, 2023-01-11 (0.0) | 0.9797, 2026-11-18 (+0.6) |
| SOPR | 0.90 | 0.928, 2022-12-05 (+0.6) | 0.8833, 2023-03-30 (+1.0) |
| RHODL | 22,000 | **none** (max 13,730) | 13,730.39, 2024-12-10 (−0.6) |
| RHODL | 5,000 | 5,003.56, 2025-11-25 (−0.6) | 4,981.19, 2025-11-27 (0.0) |
| RHODL | 1,000 | 1,001.67, 2026-05-25 (0.0) | 994.27, 2026-10-30 (+0.6) |
| RHODL | 350 | 352.06, 2023-02-21 (+0.6) | 348.09, 2023-01-16 (+1.0) |

- Every limit maps to the right band on both sides.
- SOPR has real values exactly at 1.05, 1.00 and 0.98: the inclusive lower
  bound is confirmed on real data.
- **Not testable on real data:** RHODL ≥ 22,000 (the −1.0 band has never
  fired in the BGeometrics window); covered only by the unit test. Exact
  equality at the NUPL, MVRV-Z and RHODL limits is not in real data; NUPL and
  RHODL unit tests pin it; MVRV-Z only at 0.0.

## 4. Coverage and weights: PASS (one case NOT CHECKED)

Independent rebuild of the mart from the `int_` models (as-of, expiry 3 / 3 /
10 / 3 days from the rules, weights 0.9 / 1.1 / 0.7 / 1.1) for every mart date
from 2022-11-01 (1,486 dates): **0 mismatches** in `layer_coverage`,
`layer_score`, `layer_signal` and the four `data_age` columns. Weights sum
**3.8**; minimum coverage 0.70.

| Date | Signals (NUPL / Z / SOPR / RHODL) | Coverage | Score | layer_signal |
|---|---|---|---|---|
| 2022-11-25 | +1.0 / +1.0 / — / — | 2.0 / 3.8 = 0.5263 | NULL | NULL (< 0.70) |
| 2022-11-26 | +1.0 / +1.0 / 0.0 / +1.0 | 3.8 / 3.8 = 1.0 | 3.1 / 3.8 = 0.8158 | BULLISH |
| 2026-11-25 | +0.6 / +0.6 / 0.0 / +0.6 | 1.0 | 1.86 / 3.8 = 0.4895 | BULLISH |

- **One stale indicator: NOT CHECKED on real data.** From 2022-11-26 to
  2026-11-25 there is no day with coverage below 1.0: no indicator has ever
  expired inside the layer window. The expiry logic is still exercised by the
  as-of rebuild (same results on every date) and by the mart test on
  `data_age` vs `as_of`. By hand, if SOPR expired on the last row: coverage
  3.1 / 3.8 = 0.816 (≥ 0.70), score 1.86 / 3.1 = 0.60, BULLISH. With RHODL or
  Z expired instead: 2.7 / 3.8 = 0.711, still ≥ 0.70. With two expired: at
  most 2.2 / 3.8 = 0.579, NULL.

## 5. Explicit-NULL pattern: PASS

- MVRV-Z: 0 values before 2012-01-01 and 0 values with `n_obs` < 365. The
  window starts on 2010-07-18 (`n_obs` 1); the first Z is 2012-01-01 with
  `n_obs` 533. The 365-observation rule no longer binds on real data (spec
  Q9); it stays as a guard, tested by the unit test.
- NUPL: 0 values before 2012-01-01.
- No NULL value after the first value in any `int_` model (no unexpected
  holes); `layer_score` has no NULL after 2022-11-26.

## 6. data_age and per-indicator expiry: PASS

- Last row (2026-11-25): NUPL 1, MVRV-Z 1, SOPR 6, RHODL 0, equal to the
  independent recomputation.
- Expiry in `int_onchain_btc_signals`: 3 (NUPL, MVRV-Z, RHODL) and 10 (SOPR),
  from the daily and BGeometrics freshness blocks; matches the rules.
- `data_age` is relative to the mart's `signal_date`, not to today: the
  freshest indicator always shows 0 on the last row. Staleness versus today is
  source freshness (`assert_per_metric_freshness`: PASS, both blocks).

## 7. Last row (2026-11-25): PASS

| Indicator | Observation used | Value | Band | normalized_value | Weight | Contribution |
|---|---|---|---|---|---|---|
| NUPL | 2026-11-24 (age 1) | 0.1119 | [0.00, 0.30) | +0.6 | 0.9 | 0.54 |
| MVRV-Z | 2026-11-24 (age 1) | 0.217 | [0.0, 2.0) | +0.6 | 1.1 | 0.66 |
| SOPR | 2026-11-19 (age 6, expiry 10) | 0.9839 | [0.98, 1.00) | 0.0 | 0.7 | 0.00 |
| RHODL | 2026-11-25 (age 0) | 721.83 | [350, 1,000) | +0.6 | 1.1 | 0.66 |

Score = 1.86 / 3.8 = **0.4895** ≥ 0.3 → **BULLISH**, coverage 1.0. Three of
the four indicators sit in their "+0.6 accumulation" band; SOPR is neutral.

## 8. Access: PASS

- `INFORMATION_SCHEMA.OBJECT_PRIVILEGES` on the three layer marts in
  `market_signal_marts_refactor`: **no object-level grants**.
- Dataset-level ACL of `market_signal_marts_refactor`: project roles and the
  owner only; Sara's principal is not there.
- The last refactor build ran **with `SARA_MARTS_READER_PRINCIPAL` set** and
  the grant went to the placeholder (failed as designed): the safeguard in
  `macros/sara_marts_reader.sql` works in a real build, not only in compile.

## Gotcha: PARSE_JSON exact mode drops rows silently

Found while checking the RHODL row of 2026-02-12 (reported as "unparsed" in
the first data QA).

- `PARSE_JSON` defaults to `wide_number_mode => 'exact'`, which **rejects**
  numbers that can't round-trip through FLOAT64, e.g. `1882.6654266667`:
  `Invalid input: Input number: 1882.6654266667 cannot round-trip through
  string representation`.
- `SAFE.PARSE_JSON` turns that error into **NULL, silently**. A filter on a
  JSON field then drops the row without any error.
- `PARSE_JSON(x, wide_number_mode => 'round')` parses it
  (`1882.6654266666999`).
- In `raw_market_metrics`, 2,114 payloads fail in exact mode and parse in
  round mode: dxy 1,209, vix 349, btc_price 258, move 207, mags 88, spx 2,
  btc_rhodl_ratio 1. None fails in round mode.
- **No model is affected:** no model parses `payload` (staging reads the
  `value` column with `SAFE_CAST`), and raw row counts equal model row counts
  for every on-chain series (check 1).
- **Rule:** any query or model that parses `payload` must use
  `wide_number_mode => 'round'`, or check `SAFE.PARSE_JSON(...) IS NULL`
  explicitly instead of filtering on a JSON field.

## Queries and billed bytes (QA part)

| Query | Purpose | Billed bytes |
|---|---|---|
| QA1 | Grain, uniqueness, continuity, NULL pattern (check 1, 5) | 20,971,520 |
| QA2 | Independent recomputation, all dates + spot values (check 2) | 10,485,760 |
| QA3 | Closest values around every limit (check 3) | 10,485,760 |
| QA4 | Independent mart rebuild, coverage, score, data_age (checks 4, 6, 7) | 20,971,520 |
| QA5 | Object-level grants on the refactor marts (check 8) | 10,485,760 |
| QA6 | Dataset-level grants (check 8) + MVRV-Z band shares | 20,971,520 |
| **Total** | | **94,371,840** |

Failed attempts (correlated subquery, OBJECT_PRIVILEGES filter, PARTITION BY)
were rejected at analysis and billed 0 bytes.
