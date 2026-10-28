-- Capa de liquidez cripto: una fila por día natural, una columna signal_<indicador>
-- por indicador de la capa. Cada día toma la última observación disponible de cada
-- indicador (arrastre as-of) siempre que no tenga más de max_age_days días;
-- si es más antigua, signal_<indicador> y <indicador>_as_of quedan en NULL.
-- <indicador>_as_of es la fecha de la observación usada, para que el arrastre
-- sea siempre visible.
--
-- Los dos indicadores son diarios. El ETF solo tiene sesiones de días hábiles
-- de EE. UU.: fines de semana y festivos arrastran la última sesión (hasta 3
-- días). Los flujos de exchanges se revisan durante ~30 días (ver
-- docs/indicator_rules/btc_exchange_net_flow.yaml).
--
-- layer_signal queda fuera de esta versión: la regla de combinación de la
-- capa está pendiente de definir.

{%- set indicators = ['btc_etf_net_flow', 'btc_exchange_net_flow'] %}

WITH observations AS (
    SELECT
        indicator,
        event_date,
        signal,
        max_age_days
    FROM {{ ref('int_crypto_liquidity_signals') }}
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
