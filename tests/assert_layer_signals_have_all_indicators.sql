-- Cada int_<capa>_signals debe tener filas de todos los int_<indicador> que une.
-- El peso total de la capa (denominador de layer_coverage) se calcula con los
-- indicadores presentes en int_<capa>_signals: si uno no aportara filas,
-- desaparecería en silencio del denominador e inflaría la cobertura.
--
-- Los indicadores esperados se leen de las dependencias de cada modelo en el
-- DAG (sus int_<indicador> padres), no de una lista copiada aquí.
--
-- depends_on: {{ ref('int_macro_signals') }}
-- depends_on: {{ ref('int_crypto_liquidity_signals') }}

{%- set layer_models = ['int_macro_signals', 'int_crypto_liquidity_signals'] %}
{%- set expected = [] %}
{%- if execute %}
    {%- for layer_model in layer_models %}
        {%- set node = graph.nodes['model.' ~ project_name ~ '.' ~ layer_model] %}
        {%- for parent in node.depends_on.nodes if parent.startswith('model.' ~ project_name ~ '.int_') %}
            {%- do expected.append({'layer_model': layer_model, 'indicator': parent.split('.')[-1][4:]}) %}
        {%- endfor %}
    {%- endfor %}
{%- endif %}

{% if expected | length > 0 -%}
WITH expected AS (
    {%- for e in expected %}
    SELECT '{{ e.layer_model }}' AS layer_model, '{{ e.indicator }}' AS indicator
    {{ "UNION ALL" if not loop.last }}
    {%- endfor %}
),

present AS (
    {%- for layer_model in layer_models %}
    SELECT DISTINCT '{{ layer_model }}' AS layer_model, indicator
    FROM {{ ref(layer_model) }}
    {{ "UNION ALL" if not loop.last }}
    {%- endfor %}
)

SELECT e.layer_model, e.indicator
FROM expected AS e
LEFT JOIN present AS p USING (layer_model, indicator)
WHERE p.indicator IS NULL
{%- else -%}
-- En parse (execute = false) graph aún no está poblado.
SELECT 1 AS placeholder FROM UNNEST([1]) WHERE FALSE
{%- endif %}
