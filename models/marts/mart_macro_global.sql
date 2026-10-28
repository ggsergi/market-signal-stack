-- Capa macro global: una fila por día natural, una columna signal_<indicador>
-- por indicador macro. Cada día toma la última observación disponible de cada
-- indicador (arrastre as-of) siempre que no tenga más de max_age_days días;
-- si es más antigua, signal_<indicador> y <indicador>_as_of quedan en NULL.
-- <indicador>_as_of es la fecha de la observación usada, para que el arrastre
-- sea siempre visible.
--
-- Aviso (lookahead): los indicadores mensuales están fechados en el mes al
-- que se refieren, no en su publicación. Con el arrastre, una fila puede usar
-- un dato que ese día aún no se había publicado. No afecta a la lectura diaria
-- actual; sí a un backtest. Ver docs/refactor_plan.md (D3).
--
-- layer_signal queda fuera de esta versión: la regla de combinación de la
-- capa está pendiente de definir.

{%- set indicators = ['yield_curve', 'fed_balance_sheet', 'dxy', 'vix', 'spx',
                      'nasdaq_tech_risk', 'move', 'eurozone_m3', 'usa_m2', 'china_m2'] %}

WITH observations AS (
    SELECT
        indicator,
        event_date,
        signal,
        max_age_days
    FROM {{ ref('int_macro_signals') }}
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
    SELECT DISTINCT indicator, max_age_days
    FROM observations
),

-- Una fila por (día, indicador), con la observación de ese mismo día si existe.
calendar_by_indicator AS (
    SELECT
        c.signal_date,
        i.indicator,
        i.max_age_days,
        o.event_date,
        o.signal
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
        LAST_VALUE(
            IF(event_date IS NOT NULL, STRUCT(event_date, signal), NULL) IGNORE NULLS
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
        IF(DATE_DIFF(signal_date, last_observation.event_date, DAY) <= max_age_days,
            last_observation.event_date, NULL) AS as_of_date,
        IF(DATE_DIFF(signal_date, last_observation.event_date, DAY) <= max_age_days,
            last_observation.signal, NULL) AS signal
    FROM as_of
)

SELECT
    signal_date,
    {%- for indicator in indicators %}
    MAX(IF(indicator = '{{ indicator }}', signal, NULL)) AS signal_{{ indicator }},
    {%- endfor %}
    {%- for indicator in indicators %}
    MAX(IF(indicator = '{{ indicator }}', as_of_date, NULL)) AS {{ indicator }}_as_of{{ "," if not loop.last }}
    {%- endfor %}
FROM fresh
GROUP BY signal_date
ORDER BY signal_date
