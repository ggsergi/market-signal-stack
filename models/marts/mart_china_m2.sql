{{ config(materialized='table') }}

WITH m2 AS (
    -- M2 de China (TradingEconomics, mensual, cny_billions). La normalización
    -- es por percentil sobre el propio histórico, así que la unidad no afecta
    -- y no hace falta convertirla.
    SELECT
        event_time,
        value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'm2_china'
),

with_lag AS (
    SELECT
        event_time,
        value,
        LAG(value, 12) OVER (ORDER BY event_time) AS value_12m_ago,
        LAG(event_time, 12) OVER (ORDER BY event_time) AS event_time_12m_ago
    FROM m2
),

yoy AS (
    SELECT
        event_time,
        value,
        -- Solo se calcula YoY si la fila de 12 posiciones atrás es
        -- exactamente el mismo mes del año anterior; si faltara algún mes en
        -- la serie, LAG(12) apuntaría a otro mes y el YoY sería falso.
        CASE
            WHEN DATE_DIFF(DATE(event_time), DATE(event_time_12m_ago), MONTH) = 12
                THEN (value / value_12m_ago) - 1
            ELSE NULL
        END AS m2_yoy
    FROM with_lag
),

with_window AS (
    SELECT
        event_time,
        value,
        m2_yoy,
        -- Se agrega como STRUCT porque un ARRAY no admite elementos NULL y
        -- ARRAY_AGG analítico no permite IGNORE NULLS; los NULL de m2_yoy
        -- (primeros 12 meses) se descartan al contar en UNNEST.
        ARRAY_AGG(STRUCT(m2_yoy AS yoy)) OVER (
            ORDER BY event_time
            ROWS BETWEEN 119 PRECEDING AND CURRENT ROW
        ) AS yoy_window
    FROM yoy
),

calculated AS (
    SELECT
        event_time,
        value,
        m2_yoy,
        -- Percentil = fracción de las últimas 120 observaciones de m2_yoy
        -- (incluida la actual) que son <= a la actual, en [0, 1]. Solo se
        -- calcula con la ventana de 120 meses completa (normalization.
        -- rolling_window en docs/indicator_rules/china_m2_money_supply.yaml);
        -- con menos sería un percentil sobre un histórico parcial. Con el
        -- histórico actual esto da NULL en todas las filas -- esperado, no un
        -- error; ver "Indicators in progress" en el README.
        -- PERCENT_RANK() no admite ventana deslizante en BigQuery, de ahí el
        -- ARRAY_AGG + UNNEST.
        CASE
            WHEN m2_yoy IS NOT NULL AND yoy_obs_count >= 120
                THEN yoy_le_count / yoy_obs_count
            ELSE NULL
        END AS yoy_percentile
    FROM (
        SELECT
            event_time,
            value,
            m2_yoy,
            (SELECT COUNT(w.yoy) FROM UNNEST(yoy_window) AS w) AS yoy_obs_count,
            (SELECT COUNTIF(w.yoy <= m2_yoy) FROM UNNEST(yoy_window) AS w) AS yoy_le_count
        FROM with_window
    )
)

SELECT
    event_time,
    value,
    m2_yoy,
    yoy_percentile,
    -- Percentil alto (crecimiento de M2 históricamente alto, expansión
    -- monetaria) es BULLISH: cadena descendente (">="), primer-match-gana
    -- con límite inferior inclusivo, igual que mart_eurozone_m3/mart_usa_m2.
    CASE
        WHEN yoy_percentile IS NULL THEN NULL
        WHEN yoy_percentile >= 0.9 THEN 1.0
        WHEN yoy_percentile >= 0.7 THEN 0.6
        WHEN yoy_percentile >= 0.3 THEN 0.0
        WHEN yoy_percentile >= 0.1 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN yoy_percentile IS NULL THEN NULL
        WHEN yoy_percentile >= 0.9 THEN 'BULLISH'
        WHEN yoy_percentile >= 0.7 THEN 'BULLISH'
        WHEN yoy_percentile >= 0.3 THEN 'NEUTRAL'
        WHEN yoy_percentile >= 0.1 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal,
    CASE
        WHEN yoy_percentile IS NULL THEN NULL
        WHEN yoy_percentile >= 0.9 THEN 'positive'
        WHEN yoy_percentile >= 0.7 THEN 'positive'
        WHEN yoy_percentile >= 0.3 THEN 'neutral'
        WHEN yoy_percentile >= 0.1 THEN 'negative'
        ELSE 'negative'
    END AS btc_bias,
    CASE
        WHEN yoy_percentile IS NULL THEN NULL
        WHEN yoy_percentile >= 0.9 THEN 'El crecimiento del M2 de China es extremadamente alto en términos históricos, indicando una fuerte expansión monetaria que impulsa la liquidez global y favorece activos de riesgo como BTC.'
        WHEN yoy_percentile >= 0.7 THEN 'El M2 de China está creciendo a un ritmo elevado respecto a su historial, indicando expansión monetaria y un entorno favorable para la liquidez global.'
        WHEN yoy_percentile >= 0.3 THEN 'El crecimiento del M2 de China se encuentra en niveles históricos normales, sin señales claras de expansión o contracción monetaria relevantes.'
        WHEN yoy_percentile >= 0.1 THEN 'El crecimiento del M2 de China es débil en términos históricos, señalando una contracción monetaria que puede presionar la liquidez global y BTC.'
        ELSE 'El crecimiento del M2 de China es extremadamente bajo, indicando una contracción monetaria severa o estrés económico con impacto negativo en la liquidez global y BTC.'
    END AS message
FROM calculated
ORDER BY event_time
