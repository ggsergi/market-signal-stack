{{ config(materialized='table') }}

WITH ndx AS (
    SELECT
        event_time,
        value AS close
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'ndx'
),

with_window AS (
    SELECT
        event_time,
        close,
        LAG(close) OVER (ORDER BY event_time) AS previous_close,
        AVG(close) OVER (
            ORDER BY event_time
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS ma200,
        COUNT(close) OVER (
            ORDER BY event_time
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS obs_count
    FROM ndx
),

calculated AS (
    SELECT
        event_time,
        close,
        -- Variación diaria como fracción (0.01 = +1%), misma escala que
        -- distance_to_ma200. NULL en la primera fila (sin cierre anterior).
        (close / previous_close) - 1 AS daily_change_pct,
        -- Igual que mart_spx: distance solo se calcula con la ventana de 200
        -- días completa; con menos observaciones ma200 sería una media
        -- parcial, así que distance queda NULL hasta que haya histórico.
        CASE
            WHEN obs_count >= 200 THEN (close / ma200) - 1
            ELSE NULL
        END AS distance_to_ma200
    FROM with_window
)

SELECT
    event_time,
    close,
    daily_change_pct,
    distance_to_ma200,
    -- Igual que mart_spx: distance alto (NDX por encima de su MA200) es
    -- BULLISH, cadena descendente (">="), primer-match-gana con límite
    -- inferior inclusivo. Valores literales de
    -- docs/indicator_rules/nasdaq_tech_risk_regime.yaml.
    CASE
        WHEN distance_to_ma200 IS NULL THEN NULL
        WHEN distance_to_ma200 >= 0.10 THEN 1.0
        WHEN distance_to_ma200 >= 0.02 THEN 0.6
        WHEN distance_to_ma200 >= -0.02 THEN 0.0
        WHEN distance_to_ma200 >= -0.10 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN distance_to_ma200 IS NULL THEN NULL
        WHEN distance_to_ma200 >= 0.10 THEN 'BULLISH'
        WHEN distance_to_ma200 >= 0.02 THEN 'BULLISH'
        WHEN distance_to_ma200 >= -0.02 THEN 'NEUTRAL'
        WHEN distance_to_ma200 >= -0.10 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal,
    CASE
        WHEN distance_to_ma200 IS NULL THEN NULL
        WHEN distance_to_ma200 >= 0.10 THEN 'positive'
        WHEN distance_to_ma200 >= 0.02 THEN 'positive'
        WHEN distance_to_ma200 >= -0.02 THEN 'neutral'
        WHEN distance_to_ma200 >= -0.10 THEN 'negative'
        ELSE 'negative'
    END AS btc_bias,
    CASE
        WHEN distance_to_ma200 IS NULL THEN NULL
        WHEN distance_to_ma200 >= 0.10 THEN 'El NASDAQ 100 cotiza muy por encima de su media de 200 días, indicando un entorno claramente alcista en tecnología y muy favorable para BTC.'
        WHEN distance_to_ma200 >= 0.02 THEN 'El NASDAQ 100 se mantiene por encima de su media de 200 días, reflejando fortaleza en el sector tecnológico y un entorno favorable para BTC.'
        WHEN distance_to_ma200 >= -0.02 THEN 'El NASDAQ 100 se mueve cerca de su media de 200 días, sin una dirección clara en el apetito por riesgo tecnológico.'
        WHEN distance_to_ma200 >= -0.10 THEN 'El NASDAQ 100 cotiza por debajo de su media de 200 días, señalando debilidad en tecnología y un entorno menos favorable para BTC.'
        ELSE 'El NASDAQ 100 se encuentra muy por debajo de su media de 200 días, indicando un entorno claramente bajista en tecnología y adverso para BTC.'
    END AS message
FROM calculated
ORDER BY event_time
