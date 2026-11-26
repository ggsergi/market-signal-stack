# Spec: btc_cycle layer (mart_btc_cycle) — SUPERSEDED

> **Superseded on 2026-11-26 by `docs/specs/onchain_btc_layer.md`.** The
> layer keeps the name `onchain_btc` / `mart_onchain_btc` (P5), Realized
> Price stays out (P8), RHODL has provisional bands. Kept for the record;
> don't use it as a reference.

Status: **superseded** (was: draft), nothing built. Requested on 2026-11-26: a layer mart with
NUPL, RHODL Ratio, MVRV Z-Score, SOPR and Realized Price. Numbers come from
read-only queries on `raw_market_metrics` on 2026-11-26. Indicator specs:

| Indicator | Rule | Spec | Status |
|---|---|---|---|
| NUPL | `btc_nupl_cycle_regime.yaml` | `btc_nupl_cycle_regime.md` | approved, built (`int_btc_nupl`) |
| MVRV Z-Score | `btc_mvrv_zscore.yaml` | `btc_mvrv_zscore.md` | draft |
| SOPR | `sopr_spent_output_profit_ratio.yaml` | `sopr_spent_output_profit_ratio.md` | draft |
| Realized Price | `btc_realized_price.yaml` | `btc_realized_price.md` | draft, reverses P8 |
| RHODL Ratio | `rhodl_ratio_btc.yaml` | `rhodl_ratio_btc.md` | **blocked** |

## 1. Naming (to confirm)

- Mart: **`mart_btc_cycle`** (the request says `mart_btc_cicle`; assumed a
  typo). Layer id `btc_cycle`, signals model `int_btc_cycle_signals`, layer
  rule `docs/layer_rules/btc_cycle.yaml`, same structure as the other layers
  (`layer_mart` macro, contract and grants on the mart).
- **Conflict with decision P5** (NUPL spec): the layer was named
  `onchain_btc` / `mart_onchain_btc` to avoid a clash with the planned final
  mart `mart_btc_cycle_signal`. `mart_btc_cycle` and `mart_btc_cycle_signal`
  would sit side by side. If `btc_cycle` is confirmed, `layer` in
  `btc_nupl_cycle_regime.yaml` and `meta.layer` in `int_btc_nupl.yml` change
  from `onchain_btc` to `btc_cycle`, and the NUPL spec's P5 is updated.
- The NUPL YAML sent on 2026-11-26 says `layer: onchain`; the other four say
  `btc_cycle`.
- Indicator names in the layer (and `int_` models): `btc_nupl`,
  `btc_mvrv_zscore`, `btc_sopr`, `btc_realized_price`, `btc_rhodl_ratio`.

## 2. NUPL rule: not overwritten

The NUPL YAML sent on 2026-11-26 is the original rule. The saved one is the
approved version, which already settles: Coin Metrics instead of Glassnode
(`1 − 1/btc_mvrv`), `rolling_window: null` (P3), NULL before 2012 (P1), the
rewritten [0.00, 0.30) message (P11) and the reference points (P7). The saved
file is kept; only `layer` may change (§1).

## 3. Sources

| Indicator | Source | History | Latency |
|---|---|---|---|
| NUPL | Coin Metrics `btc_mvrv` | 2012-01-01 (start date) | 2 days |
| MVRV Z-Score | Coin Metrics `btc_market_cap`, `btc_mvrv` | 2012-12-30 (365-obs minimum) | 2 days |
| Realized Price | Coin Metrics `btc_mvrv` (distance = MVRV − 1) | 2012-01-01 | 2 days |
| SOPR | BGeometrics `btc_sopr` | 2022-11-26 | **7 days** |
| RHODL | BGeometrics `btc_rhodl_ratio` | 2022-11-26 | 1 day |

None of the Glassnode series named in the rules is in the raw layer.
BGeometrics also loaded `btc_nupl`, `btc_mvrv_zscore` and
`btc_realized_price`. They match the Coin Metrics derivations (NUPL max
difference 0.03, Z correlation 1.000, realized price within 0.84 %), but
they only cover 4 years with a 7-day lag, so they're kept as cross-checks
only.

## 4. Redundancy

NUPL, MVRV Z-Score and Realized Price are all functions of MVRV (Z also of
market cap). Share of the layer's weight driven by MVRV:

| Composition | Total weight | MVRV-driven weight | Share |
|---|---|---|---|
| All five | 4.7 | 2.9 | 62 % |
| Without RHODL | 3.6 | 2.9 | 81 % |
| Without RHODL and Realized Price | 2.7 | 2.0 | 74 % |

The layer is in practice an MVRV indicator with SOPR (and, later, RHODL) on
top. That isn't wrong, but it should be a conscious choice (Q2).

## 5. Coverage (min 70 %, as in the other layers)

Weights from the rules: NUPL 0.9, RHODL 1.1, Z 1.1, SOPR 0.7, Realized Price
0.9.

- **All five (4.7; 70 % = 3.29):** before 2022-11-26 only the three Coin
  Metrics indicators exist: 2.9 / 4.7 = 62 %, so **`layer_signal` is NULL
  from 2012 to 2022-11-25**. And RHODL, as blocked, would add −1.0 every day.
- **Without RHODL (3.6; 70 % = 2.52):** the Coin Metrics trio gives 81 %, so
  `layer_signal` exists from 2012-12-30 (first Z value). SOPR missing or
  expired doesn't drop the layer.
- **Without RHODL and Realized Price (2.7; 70 % = 1.89):** NUPL + Z = 74 %;
  same start date.

## 6. Freshness and expiry

- `max_age_days` of each indicator is read from a freshness block in
  `_sources.yml` (`freshness_error_after_days`). The daily block has
  `error_after` 3 days.
- SOPR's 7-day latency means it is always expired on the last ~4 days of the
  mart. Proposal: a new block for BGeometrics (filter `source =
  'BGeometrics'`, `error_after` ~10 days) used as SOPR's and RHODL's
  `freshness_block`.
- Coin Metrics on-chain series (`btc_mvrv`, `btc_market_cap`) are in no
  freshness block today (P4, open with Sara). They would need to be added to
  the daily filter, or `assert_per_metric_freshness` won't cover them.

## 7. Proposal

1. Layer with **NUPL, MVRV Z-Score and SOPR** now.
2. **RHODL out** until its thresholds fit the data (blocked).
3. **Realized Price**: include only if P8 is reversed explicitly; otherwise
   out (redundant with NUPL, and its bands are not monotonic).
4. New freshness block for BGeometrics; Coin Metrics on-chain metrics added
   to the daily filter.

## 8. Open questions

- **Q1.** Mart name `mart_btc_cycle` (typo in the request)? Layer `btc_cycle`
  instead of `onchain_btc` (reverses P5)?
- **Q2.** Accept that ~60-80 % of the layer's weight comes from MVRV?
- **Q3.** RHODL: where do its thresholds come from? (blocking)
- **Q4.** Realized Price in or out (P8)?
- **Q5.** Weights and relevance marked "TO CONFIRM" in the MVRV-Z rule
  (3 / 1.1); NUPL's relevance 2 vs Notion's 3.
- **Q6.** Freshness block for BGeometrics and P4 (for Sara).
