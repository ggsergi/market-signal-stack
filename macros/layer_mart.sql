{#
    Cuerpo común de los marts de capa (mart_macro_global, mart_crypto_liquidity):
    las mismas reglas para todas las capas, en un solo sitio.

    Entrada: `signals_model`, un int_<capa>_signals en formato largo (indicator,
    event_date, signal, normalized_value, weight, max_age_days), y `indicators`,
    la lista de indicadores de la capa (una columna signal_<indicador> y
    <indicador>_as_of por cada uno, en ese orden).

    Salida: una fila por día natural.
    - signal_<indicador> / <indicador>_as_of: cada día toma la última observación
      del indicador (arrastre as-of) si no tiene más de max_age_days días; si es
      más antigua, ambas columnas quedan en NULL.
    - layer_score / layer_coverage / layer_signal: reglas de
      docs/layer_rules/<capa>.yaml (iguales en todas las capas):
        layer_score    = SUM(normalized_value * weight) / SUM(weight), solo sobre
                         los indicadores con señal ese día (arrastrada y no
                         caducada incluida).
        layer_coverage = SUM(weight con señal) / SUM(weight de toda la capa).
        Si layer_coverage < 0.70: layer_score y layer_signal NULL.
        layer_signal   = BULLISH si >= 0.3; NEUTRAL si [-0.3, 0.3); BEARISH si < -0.3.
      Aritmética NUMERIC (decimal exacta): pesos y valores son decimales y los
      cortes caen justo en ellos (p. ej. cobertura 7.7 / 11 = 0.70).
    - <indicador>_data_age_days (only with include_data_age=true; opt-in so
      the other layer marts and their contracts stay unchanged): days between
      signal_date and the indicator's latest observation up to that day,
      published even when that observation has expired (signal_<indicador>
      and <indicador>_as_of NULL), so a consumer can weigh how stale each
      signal is. NULL only before the indicator's first observation.
#}
{% macro layer_mart(signals_model, indicators, include_data_age=false) %}

WITH observations AS (
    SELECT
        indicator,
        event_date,
        signal,
        normalized_value,
        weight,
        max_age_days
    FROM {{ ref(signals_model) }}
),

-- Calendario: del primer día con alguna señal no nula a la última fecha con
-- observaciones de cualquier indicador.
calendar AS (
    SELECT signal_date
    FROM UNNEST(GENERATE_DATE_ARRAY(
        (SELECT MIN(event_date) FROM observations WHERE signal IS NOT NULL),
        (SELECT MAX(event_date) FROM observations)
    )) AS signal_date
),

indicator_list AS (
    SELECT DISTINCT indicator, max_age_days, weight
    FROM observations
),

-- Una fila por (día, indicador), con la observación de ese mismo día si existe.
calendar_by_indicator AS (
    SELECT
        c.signal_date,
        i.indicator,
        i.max_age_days,
        i.weight,
        o.event_date,
        o.signal,
        o.normalized_value
    FROM calendar AS c
    CROSS JOIN indicator_list AS i
    LEFT JOIN observations AS o
        ON o.indicator = i.indicator
        AND o.event_date = c.signal_date
),

-- Arrastre as-of: la última observación hasta ese día (incluido). Se arrastra
-- como STRUCT para que una observación con signal NULL (ventana incompleta)
-- se respete como NULL y no se salte a una señal anterior.
as_of AS (
    SELECT
        signal_date,
        indicator,
        max_age_days,
        weight,
        LAST_VALUE(
            IF(event_date IS NOT NULL, STRUCT(event_date, signal, normalized_value), NULL) IGNORE NULLS
        ) OVER (
            PARTITION BY indicator
            ORDER BY signal_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_observation
    FROM calendar_by_indicator
),

-- Caducidad: igual que source freshness (error_after), válido mientras la
-- antigüedad no supere max_age_days.
fresh AS (
    SELECT
        signal_date,
        indicator,
        weight,
        IF(DATE_DIFF(signal_date, last_observation.event_date, DAY) <= max_age_days,
            last_observation.event_date, NULL) AS as_of_date,
        IF(DATE_DIFF(signal_date, last_observation.event_date, DAY) <= max_age_days,
            last_observation.signal, NULL) AS signal,
        IF(DATE_DIFF(signal_date, last_observation.event_date, DAY) <= max_age_days,
            last_observation.normalized_value, NULL) AS normalized_value,
        DATE_DIFF(signal_date, last_observation.event_date, DAY) AS data_age_days
    FROM as_of
),

by_day AS (
    SELECT
        signal_date,
        {%- for indicator in indicators %}
        MAX(IF(indicator = '{{ indicator }}', signal, NULL)) AS signal_{{ indicator }},
        {%- endfor %}
        {%- for indicator in indicators %}
        MAX(IF(indicator = '{{ indicator }}', as_of_date, NULL)) AS {{ indicator }}_as_of,
        {%- endfor %}
        {%- if include_data_age %}
        {%- for indicator in indicators %}
        MAX(IF(indicator = '{{ indicator }}', data_age_days, NULL)) AS {{ indicator }}_data_age_days,
        {%- endfor %}
        {%- endif %}
        SUM(IF(signal IS NOT NULL, CAST(normalized_value AS NUMERIC) * weight, NULL)) AS weighted_sum,
        SUM(IF(signal IS NOT NULL, weight, NUMERIC '0')) AS weight_with_signal,
        SUM(weight) AS weight_total
    FROM fresh
    GROUP BY signal_date
),

scored AS (
    SELECT
        *,
        weight_with_signal / weight_total AS layer_coverage,
        IF(weight_with_signal / weight_total >= NUMERIC '0.70',
            weighted_sum / weight_with_signal, NULL) AS layer_score
    FROM by_day
)

SELECT
    signal_date,
    {%- for indicator in indicators %}
    signal_{{ indicator }},
    {%- endfor %}
    {%- for indicator in indicators %}
    {{ indicator }}_as_of,
    {%- endfor %}
    {%- if include_data_age %}
    {%- for indicator in indicators %}
    {{ indicator }}_data_age_days,
    {%- endfor %}
    {%- endif %}
    layer_score,
    layer_coverage,
    -- Primer-match-gana con límite inferior inclusivo ([min_inclusive,
    -- max_exclusive) en docs/layer_rules/).
    CASE
        WHEN layer_score IS NULL THEN NULL
        WHEN layer_score >= NUMERIC '0.3' THEN 'BULLISH'
        WHEN layer_score >= NUMERIC '-0.3' THEN 'NEUTRAL'
        ELSE 'BEARISH'
    END AS layer_signal
FROM scored
ORDER BY signal_date

{% endmacro %}
