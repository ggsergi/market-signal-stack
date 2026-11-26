-- On-chain BTC layer signals in long format: one row per (indicator,
-- observation date). Unions the int_<indicator> models with UNION ALL (no
-- JOIN); mart_onchain_btc does the pivot to one row per day and the as-of
-- carry-forward.
--
-- max_age_days: per-indicator expiry of the as-of carry-forward, the
-- error_after of each indicator's freshness block in _sources.yml (read from
-- there, not copied). NUPL, MVRV-Z (Coin Metrics, ~2-day lag) and RHODL
-- (BGeometrics, 1-day lag) use the daily block (3 days); SOPR (BGeometrics
-- free plan, ~7-day lag) uses the BGeometrics block (10 days).
--
-- weight: the indicator's weight in layer_score, the meta.weight of its
-- int_<indicator>.yml (exact copy of the weight in docs/indicator_rules/).

{%- set indicators = [
    {'name': 'btc_nupl',         'freshness_block': 'raw_market_metrics'},
    {'name': 'btc_mvrv_zscore',  'freshness_block': 'raw_market_metrics'},
    {'name': 'btc_sopr',         'freshness_block': 'raw_market_metrics_bgeometrics'},
    {'name': 'btc_rhodl_ratio',  'freshness_block': 'raw_market_metrics'},
] %}

{% for indicator in indicators %}
SELECT
    '{{ indicator.name }}' AS indicator,
    DATE(event_time) AS event_date,
    signal,
    normalized_value,
    {{ freshness_error_after_days(indicator.freshness_block) }} AS max_age_days,
    CAST('{{ indicator_weight('int_' ~ indicator.name) }}' AS NUMERIC) AS weight
FROM {{ ref('int_' ~ indicator.name) }}
{% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
