# Spec: btc_realized_price (parked)

Status: **parked** (2026-11-26). Not part of the `onchain_btc` layer and no
model is built: decision P8 of `docs/specs/btc_nupl_cycle_regime.md` stands.
Rule kept for reference: `docs/indicator_rules/btc_realized_price.yaml`.
Numbers below come from read-only queries on `raw_market_metrics` on
2026-11-26.

Why it's parked:
1. **Redundant:** with Coin Metrics, distance = MVRV − 1 exactly, the same
   input as NUPL and MVRV-Z.
2. **Bands not monotonic** (+0.6 on both sides of a 0.0 band).
3. **−0.6 on 100 % of days** in 2013, 2017, 2021, 2024 and 2025.

## 1. Goal

Realized Price = realized cap / supply: the average price at which every coin
last moved, i.e. the network's aggregate cost basis. The indicator is the
distance of spot price from it.

## 2. Source and formula

Formula from the rule: `distance = spot_price / realized_price − 1`. The
original rule (Notion) named Glassnode, which is not in the raw layer. If it
is ever built, the source is **Coin Metrics** (decided):

- realized price = `btc_market_cap / btc_mvrv / btc_supply`
- spot price = `btc_market_cap / btc_supply`
- distance = spot / realized − 1 = **`btc_mvrv − 1` exactly** (supply
  cancels).

Cross-check: BGeometrics' `btc_realized_price` matches the Coin Metrics
derivation within 0.84 % (max deviation); Yahoo's `btc_price` deviates from
Coin Metrics' price by ≤ 0.07 % on yearly average.

## 3. Bands

Rule bands, `[min_inclusive, max_exclusive)`, with their MVRV and NUPL
equivalents (distance = MVRV − 1; NUPL = 1 − 1/MVRV):

| distance | MVRV | NUPL | normalized_value | signal |
|---|---|---|---|---|
| ≥ 0.30 | ≥ 1.30 | ≥ 0.23 | −0.6 | BEARISH |
| [0.05, 0.30) | [1.05, 1.30) | [0.05, 0.23) | 0.6 | BULLISH |
| [−0.05, 0.05) | [0.95, 1.05) | [−0.05, 0.05) | 0.0 | NEUTRAL |
| [−0.30, −0.05) | [0.70, 0.95) | [−0.43, −0.05) | 0.6 | BULLISH |
| < −0.30 | < 0.70 | < −0.43 | 1.0 | BULLISH |

Share of days per band (−0.6 / 0 / +0.6 / +1.0; −1.0 doesn't exist in this
rule):

| Year | −0.6 | 0 | +0.6 | +1.0 |
|---|---|---|---|---|
| 2013 | 100 % | 0 % | 0 % | 0 % |
| 2015 | 9 % | 13 % | 76 % | 2 % |
| 2017 | 100 % | 0 % | 0 % | 0 % |
| 2018 | 57 % | 0 % | 42 % | 1 % |
| 2021 | 100 % | 0 % | 0 % | 0 % |
| 2022 | 36 % | 12 % | 52 % | 0 % |
| 2024 | 100 % | 0 % | 0 % | 0 % |
| 2025 | 100 % | 0 % | 0 % | 0 % |
| 2026 | 57 % | 0 % | 43 % | 0 % |

## 4. Agreement with NUPL: two definitions

Same input (Coin Metrics MVRV), both rules applied per day; 2012-01-01 to
2026-11-24. `sign` is the sign of `normalized_value` (−, 0, +).

| Definition | Exact meaning | 2012-2023 | 2024-2026 |
|---|---|---|---|
| **Strictly opposite sign** | `SIGN(rp) * SIGN(nupl) < 0`: one BULLISH and the other BEARISH | 9.8 % | 5.9 % |
| **Different signal** | `SIGN(rp) != SIGN(nupl)`: includes NEUTRAL against BULLISH or BEARISH | **60.3 %** | **80.6 %** |

- The "60 % / 82 %" in the NUPL spec is the **different signal**
  definition (82 % was measured on data up to 2026-11-10; 80.6 % today). It is
  not "opposite sign" in the strict sense. The NUPL spec is corrected to
  say so.
- Most of the disagreement is Realized Price at −0.6 BEARISH while NUPL is
  0.0 NEUTRAL (MVRV between 1.43 and 2.50): 55.4 % of days in 2012-2023 and
  80.6 % in 2024-2026 have Realized Price bearish and NUPL not bearish.

## 5. If it is ever un-parked

- Model `int_btc_realized_price` (view), columns `event_time`, `mvrv`,
  `realized_price`, `spot_price`, `distance`, `normalized_value`, `signal`,
  `btc_bias`, `message`; NULL before 2012-01-01 and if `btc_mvrv` is NULL or
  ≤ 0.
- Test `ABS(distance - (mvrv - 1)) < 1e-9` to pin the identity.
- Decide first: monotonic bands, and `rolling_window: null`.
