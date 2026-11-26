# Spec: onchain_btc layer (mart_onchain_btc)

Status: **closed** (2026-11-26). Built in the refactor target
(`market_signal_marts_refactor`): `int_btc_mvrv_zscore`, `int_btc_sopr`,
`int_btc_rhodl_ratio`, `int_onchain_btc_signals`, `mart_onchain_btc`;
`int_btc_nupl` already existed. Layer rule: `docs/layer_rules/onchain_btc.yaml`.
Replaces `docs/specs/btc_cycle_layer.md`. Numbers come from read-only queries
on `raw_market_metrics` and the refactor build on 2026-11-26.

## 1. Naming

- Layer `onchain_btc`, mart **`mart_onchain_btc`** (decision P5 of the NUPL
  spec stands; "mart_btc_cicle" in the request was a typo). Signals model
  `int_onchain_btc_signals`, layer rule `docs/layer_rules/onchain_btc.yaml`,
  same structure as the other layers (`layer_mart` macro, contract and grants
  on the mart).
- All rules in the layer have `layer: onchain_btc`.

## 2. Indicators

| Indicator | Model | Rule | Source | Weight | History | Latency | Status |
|---|---|---|---|---|---|---|---|
| NUPL | `int_btc_nupl` | `btc_nupl_cycle_regime.yaml` | Coin Metrics (`btc_mvrv`) | 0.9 | 2012-01-01 | 2 days | built |
| MVRV Z-Score | `int_btc_mvrv_zscore` | `btc_mvrv_zscore.yaml` | Coin Metrics (`btc_market_cap`, `btc_mvrv`) | 1.1 (TO CONFIRM) | 2012-01-01 (window from 2010-07-18) | 2 days | built; Q3, Q4, Q7, Q8, Q9 PENDING |
| SOPR | `int_btc_sopr` | `sopr_spent_output_profit_ratio.yaml` | BGeometrics (`btc_sopr`) | 0.7 | 2022-11-26 | 7 days (free plan) | built; variant to confirm |
| RHODL Ratio | `int_btc_rhodl_ratio` | `rhodl_ratio_btc.yaml` | BGeometrics (`btc_rhodl_ratio`) | 1.1 | 2022-11-26 | 1 day | built; PROVISIONAL bands |

Total weight **3.8**.

**Out:** Realized Price, parked (P8 stands; `docs/specs/btc_realized_price.md`).

None of the Glassnode series named in the original rules (Notion) is in the
raw layer; each rule states its real source. BGeometrics also loaded
`btc_nupl`, `btc_mvrv_zscore` and `btc_realized_price`; they match the
Coin Metrics derivations and are kept only as cross-checks.

## 3. MVRV family (redundancy, accepted)

NUPL and MVRV-Z are both functions of MVRV (Z also of market cap): the
**MVRV family**. Weight: 0.9 + 1.1 = 2.0 of 3.8, **~53 %** of the layer.

Accepted and left as is: weights are not changed now (MVRV-Z's 1.1 is still
to confirm). To be reviewed once the agent uses the layer signal, e.g. if
the layer just echoes MVRV.

## 4. Coverage (min 70 %, unchanged)

Same rule as the other layers: `layer_score` and `layer_signal` are NULL if
the weight of the indicators with a (non-expired) signal is below 70 % of 3.8
(= 2.66).

| Case | Weight with signal | Coverage | layer_signal |
|---|---|---|---|
| All four | 3.8 | 100 % | yes |
| One missing (worst: Z or RHODL, 1.1) | 2.7 | 71.1 % | yes |
| One missing (SOPR, 0.7) | 3.1 | 81.6 % | yes |
| Two missing (best case: NUPL + SOPR) | 2.2 | 57.9 % | NULL |
| Only NUPL + Z (before 2022-11-26) | 2.0 | 52.6 % | NULL |

- **`layer_signal` is NULL until 2022-11-25**: before the BGeometrics series
  start, only the MVRV family exists. The threshold is not lowered to create
  history.
- The `int_` models keep their full history (NUPL from 2012, Z from
  2012-01-01, window from 2010-07-18) for backtests.
- With one indicator missing the layer survives; with two, it's NULL.
- **Checked in the build:** 2022-11-25 coverage 0.526, `layer_signal` NULL;
  2022-11-26 coverage 1.0, BULLISH. Test
  `signal_date >= '2022-11-26' OR layer_signal IS NULL` passes.

## 5. Freshness and expiry (per indicator)

`max_age_days` per indicator, read from the freshness block of each one in
`_sources.yml` (macro `freshness_error_after_days`), as in the other layers:

| Indicator | Freshness block | max_age_days |
|---|---|---|
| NUPL, MVRV-Z | daily block (`raw_market_metrics`) | 3 |
| SOPR | BGeometrics block (`raw_market_metrics_bgeometrics`, filter `source = 'BGeometrics'`) | 10 |
| RHODL | daily block (`btc_rhodl_ratio` added to the daily filter) | 3 |

Each value is also written in the indicator's rule (`freshness.max_age_days`),
except NUPL's rule, which was not touched (only its `layer` field could be).

- The new block is needed so SOPR (7-day latency) isn't expired on the last
  days of the mart every day. SOPR's max_age is ~10 days: 7 observed plus
  margin (decided).
- **SOPR's lag is a BGeometrics free-plan limitation** (confirmed by Sara,
  2026-11-26; closed). It would disappear with a paid plan or a different
  source; we are not paying for data. RHODL is slow-moving, so its lag barely
  matters; SOPR is a short-term oscillator, so the lag reduces its
  usefulness, which is one reason it has the lowest weight (0.7).
- **Fallback for SOPR (documented, not implemented):** if it proves too
  stale to be useful, exclude it from `layer_signal` and keep it only as an
  individual indicator. Coverage without SOPR: 3.1 / 3.8 = 82 %, above the
  70 % minimum.
- RHODL (1-day lag) uses the daily block: expiry 3 days (1 observed + 2
  margin; decided 2026-11-26, option A). `btc_rhodl_ratio` is in the daily
  filter list and still matches the BGeometrics block, so
  `assert_per_metric_freshness` checks it against both (3 and 10 days).
  Without RHODL the layer keeps 2.7 / 3.8 = 71 % coverage.
- The BGeometrics block is picked up automatically by
  `assert_per_metric_freshness` (it reads every block on
  `raw_market_metrics`), so a BGeometrics metric that stops loading for more
  than 10 days shows up there.
- **PENDING (P4):** `btc_mvrv` and `btc_market_cap` are not in the daily
  filter yet, so neither the source freshness nor
  `assert_per_metric_freshness` covers them. Their expiry in the mart (3 days
  from the daily block) does work, because the as-of uses `event_time`.

## 6. Data age column (decided)

The mart publishes, per indicator, **`<indicator>_data_age_days`**: the days
between the mart date (`signal_date`) and the indicator's latest available
`event_time`, so the downstream agent can weigh how stale each signal is.

- `<indicator>_data_age_days = DATE_DIFF(signal_date, last_observation.event_date, DAY)`,
  using the same as-of observation the `layer_mart` macro already picks.
- **Published even when the observation has expired** (`signal_<indicator>`
  and `<indicator>_as_of` NULL), so the agent sees how old the last data is,
  not just that it's missing. NULL only before the indicator's first
  observation.
- Last row in the build (2026-11-25, the latest RHODL date): SOPR 6, RHODL 0,
  NUPL / Z 1. **Relative to the mart's last date, not to today:** the freshest
  indicator always shows 0 on the last row. Staleness versus today is handled
  by source freshness (`_sources.yml`, `assert_per_metric_freshness`).
- The mart calendar ends on the latest date with observations of any
  indicator, not on today: the agent should also read the mart's last
  `signal_date`.
- **Implemented as an opt-in parameter** of the shared `layer_mart` macro
  (`include_data_age=true`, only in `mart_onchain_btc`), so
  `mart_macro_global` and `mart_crypto_liquidity` and their contracts don't
  change. Extending it to the other layers is one argument per mart plus the
  new columns in their contracts.

## 7. Layer rule

Same as `crypto_liquidity` and `macro_global`: `layer_score` =
`SUM(normalized_value * weight) / SUM(weight)` over indicators with a signal,
NUMERIC arithmetic; `layer_signal` BULLISH ≥ 0.3, NEUTRAL [−0.3, 0.3),
BEARISH < −0.3.

## 8. Open items (PENDING)

- MVRV-Z spec: Q3 (4-7 band ASSUMED), Q4 (falling peaks), Q7 (weight 1.1
  TO CONFIRM), Q8 / P4 (freshness), Q9 (output start date 2012-01-01 vs
  2011-07-17). Formula, window (from the first data point), sample std and
  the 2021 reference were settled on 2026-11-26.
- RHODL: PROVISIONAL bands, middle bands ASSUMED; recalibrate with more
  history.
- P4: `btc_mvrv` and `btc_market_cap` in the daily freshness filter.
- For Sara: SOPR variant; any free way to get more than 4 years of history.
  (SOPR lag: closed.)
