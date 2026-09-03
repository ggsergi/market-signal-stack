{{ config(materialized='table') }}

WITH dxy AS (
    SELECT
        event_time,
        value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'dxy'
),

with_window AS (
    SELECT
        event_time,
        value,
        AVG(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
        ) AS ma50,
        COUNT(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
        ) AS obs_count
    FROM dxy
),

calculated AS (
    SELECT
        event_time,
        value,
        ma50,
        -- Solo se calcula distance cuando la ventana de 50 días está completa
        -- (obs_count = 50). Con menos observaciones, ma50 sería una media
        -- parcial, no una MA50 real, así que distance/normalized_value/signal
        -- se dejan en NULL hasta que haya suficiente histórico.
        CASE
            WHEN obs_count >= 50 THEN (value / ma50) - 1
            ELSE NULL
        END AS distance
    FROM with_window
)

SELECT
    event_time,
    value,
    ma50,
    distance,
    -- A diferencia de yield_curve/fed_balance_sheet, aquí un distance más
    -- bajo (dólar débil) es BULLISH y uno más alto (dólar fuerte) es
    -- BEARISH -- la cadena de condiciones va en ascendente ("<") en vez de
    -- descendente (">="), pero sigue siendo primer-match-gana con límite
    -- inferior inclusivo, igual que los otros indicadores.
    CASE
        WHEN distance IS NULL THEN NULL
        WHEN distance < -0.05 THEN 1.0
        WHEN distance < -0.01 THEN 0.6
        WHEN distance < 0.01 THEN 0.0
        WHEN distance < 0.05 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN distance IS NULL THEN NULL
        WHEN distance < -0.05 THEN 'BULLISH'
        WHEN distance < -0.01 THEN 'BULLISH'
        WHEN distance < 0.01 THEN 'NEUTRAL'
        WHEN distance < 0.05 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal
FROM calculated
ORDER BY event_time
