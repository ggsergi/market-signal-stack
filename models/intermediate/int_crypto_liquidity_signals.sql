-- Señales de la capa de liquidez cripto en formato largo: una fila por (indicador, fecha
-- de observación). Une los int_<indicador> con UNION ALL (sin JOIN); el pivot
-- a una fila por día y el arrastre as-of los hace mart_crypto_liquidity.
--
-- max_age_days: caducidad del arrastre as-of de cada indicador, igual al
-- error_after del bloque de freshness de su cadencia en _sources.yml (diario,
-- semanal o mensual). Se lee de ahí, no se copia.
--
-- weight: peso del indicador en el layer_score, el meta.weight de su
-- int_<indicador>.yml (copia exacta del weight de docs/indicator_rules/).

{%- set indicators = [
    {'name': 'btc_etf_net_flow',      'freshness_block': 'raw_market_metrics'},
    {'name': 'btc_exchange_net_flow', 'freshness_block': 'raw_market_metrics'},
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
