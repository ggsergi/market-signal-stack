-- Señales de la capa macro en formato largo: una fila por (indicador, fecha
-- de observación). Une los int_<indicador> con UNION ALL (sin JOIN); el pivot
-- a una fila por día y el arrastre as-of los hace mart_macro_global.
--
-- max_age_days: caducidad del arrastre as-of de cada indicador, igual al
-- error_after del bloque de freshness de su cadencia en _sources.yml (diario,
-- semanal o mensual). Se lee de ahí, no se copia.

{%- set indicators = [
    {'name': 'yield_curve',       'freshness_block': 'raw_market_metrics'},
    {'name': 'fed_balance_sheet', 'freshness_block': 'raw_market_metrics_weekly'},
    {'name': 'dxy',               'freshness_block': 'raw_market_metrics'},
    {'name': 'vix',               'freshness_block': 'raw_market_metrics'},
    {'name': 'spx',               'freshness_block': 'raw_market_metrics'},
    {'name': 'nasdaq_tech_risk',  'freshness_block': 'raw_market_metrics'},
    {'name': 'move',              'freshness_block': 'raw_market_metrics'},
    {'name': 'eurozone_m3',       'freshness_block': 'raw_market_metrics_monthly'},
    {'name': 'usa_m2',            'freshness_block': 'raw_market_metrics_monthly'},
    {'name': 'china_m2',          'freshness_block': 'raw_market_metrics_monthly'},
] %}

{% for indicator in indicators %}
SELECT
    '{{ indicator.name }}' AS indicator,
    DATE(event_time) AS event_date,
    signal,
    normalized_value,
    {{ freshness_error_after_days(indicator.freshness_block) }} AS max_age_days
FROM {{ ref('int_' ~ indicator.name) }}
{% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
