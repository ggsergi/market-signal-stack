-- Freshness por métrica individual. Los bloques de source freshness de
-- _sources.yml (raw_market_metrics, _weekly, _monthly) calculan un único
-- MAX(loaded_at_field) sobre todo su filtro: si una métrica deja de cargar
-- pero las demás del mismo bloque siguen entrando, el bloque sigue en PASS.
-- Este test aplica el mismo filtro y el mismo error_after de cada bloque,
-- pero agrupando por metric, y devuelve una fila por cada métrica caída.
--
-- Fuente única de verdad: filtro, loaded_at_field y error_after se leen de
-- la definición de cada bloque en _sources.yml (vía graph), no se copian
-- aquí. Cambiar un umbral allí lo cambia también en este test.
--
-- depends_on: {{ source('market_signal_stack', 'raw_market_metrics') }}

-- warn y no error: una sola métrica caída no debe parar el build diario
-- completo (el resto de marts se sigue refrescando); se ve en el log. Se
-- revisará a error cuando el pipeline de ingesta esté más maduro.
{{ config(severity='warn') }}

{%- set seconds_per_period = {'minute': 60, 'hour': 3600, 'day': 86400} -%}
{%- set blocks = [] -%}
{%- if execute -%}
    {%- for node in graph.sources.values()
        if node.source_name == 'market_signal_stack'
        and node.identifier == 'raw_market_metrics'
        and node.freshness and node.freshness.error_after
        and node.freshness.error_after.count -%}
        {%- do blocks.append(node) -%}
    {%- endfor -%}
    {%- if blocks | length == 0 -%}
        {{ exceptions.raise_compiler_error("assert_per_metric_freshness: no hay bloques de freshness sobre raw_market_metrics en _sources.yml") }}
    {%- endif -%}
{%- endif %}

{% if blocks | length > 0 -%}
WITH per_metric AS (
    {%- for block in blocks %}
    {%- set error_after = block.freshness.error_after %}
    SELECT
        '{{ block.name }}' AS freshness_block,
        metric,
        MAX({{ block.loaded_at_field }}) AS last_loaded_at,
        '{{ error_after.count }} {{ error_after.period }}' AS error_after,
        {{ error_after.count * seconds_per_period[error_after.period] }} AS error_after_seconds
    FROM {{ source('market_signal_stack', 'raw_market_metrics') }}
    WHERE {{ block.freshness.filter or 'TRUE' }}
    GROUP BY metric
    {% if not loop.last %}UNION ALL{% endif %}
    {%- endfor %}
)

SELECT
    freshness_block,
    metric,
    last_loaded_at,
    error_after,
    ROUND(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_loaded_at, SECOND) / 86400, 1) AS days_since_last_load
FROM per_metric
WHERE TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_loaded_at, SECOND) > error_after_seconds
{%- else -%}
-- En parse (execute = false) graph aún no está poblado.
SELECT 1 AS placeholder FROM UNNEST([1]) WHERE FALSE
{%- endif %}
