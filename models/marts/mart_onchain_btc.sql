-- On-chain BTC layer: one row per calendar day, one signal_<indicator> column
-- per indicator. Each day takes each indicator's latest observation (as-of
-- carry-forward) as long as it is not older than its max_age_days (3 days for
-- NUPL, MVRV-Z and RHODL, 10 for SOPR); if it is older, signal_<indicator>
-- and <indicator>_as_of are NULL. <indicator>_as_of is the date of the
-- observation used, so the carry-forward is always visible.
--
-- <indicator>_data_age_days: days between signal_date and the indicator's
-- latest observation, published even when it has expired, so the agent can
-- weigh how stale each signal is (SOPR lags ~7 days on the BGeometrics free
-- plan). It is relative to the mart's signal_date, NOT to today: the calendar
-- ends on the latest date with observations of any indicator, so the
-- freshest indicator always shows 0 on the last row. Staleness versus today
-- is handled by source freshness (_sources.yml, assert_per_metric_freshness).
--
-- layer_score / layer_coverage / layer_signal: rules in
-- docs/layer_rules/onchain_btc.yaml, the same in every layer. With a 70 %
-- minimum coverage, layer_signal is NULL before 2022-11-26 (only NUPL and
-- MVRV-Z exist before the BGeometrics series start: 2.0 / 3.8 = 53 %).
--
-- The body is shared by every layer mart: macros/layer_mart.sql.

{%- set indicators = ['btc_nupl', 'btc_mvrv_zscore', 'btc_sopr', 'btc_rhodl_ratio'] %}

{{ layer_mart('int_onchain_btc_signals', indicators, include_data_age=true) }}
