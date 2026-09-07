{{ config(materialized='table') }}

WITH spx AS (
    SELECT
        event_time,
        value
    FROM {{ ref('stg_market_metrics') }}
    WHERE metric = 'spx'
),

with_window AS (
    SELECT
        event_time,
        value,
        AVG(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS ma200,
        COUNT(value) OVER (
            ORDER BY event_time
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS obs_count
    FROM spx
),

calculated AS (
    SELECT
        event_time,
        value,
        ma200,
        -- Solo se calcula distance cuando la ventana de 200 días está
        -- completa (obs_count >= 200). Con menos observaciones, ma200 sería
        -- una media parcial, no una MA200 real, así que distance queda NULL
        -- hasta que haya suficiente histórico (ver "Indicadores en
        -- construcción" en el README).
        CASE
            WHEN obs_count >= 200 THEN (value / ma200) - 1
            ELSE NULL
        END AS distance
    FROM with_window
)

SELECT
    event_time,
    value,
    ma200,
    distance,
    -- Igual que yield_curve/fed_balance_sheet: distance alto (SPX por
    -- encima de su MA200) es BULLISH, así que la cadena va descendente
    -- (">="), sin invertir como en DXY/VIX.
    CASE
        WHEN distance IS NULL THEN NULL
        WHEN distance >= 0.10 THEN 1.0
        WHEN distance >= 0.02 THEN 0.6
        WHEN distance >= -0.02 THEN 0.0
        WHEN distance >= -0.10 THEN -0.6
        ELSE -1.0
    END AS normalized_value,
    CASE
        WHEN distance IS NULL THEN NULL
        WHEN distance >= 0.10 THEN 'BULLISH'
        WHEN distance >= 0.02 THEN 'BULLISH'
        WHEN distance >= -0.02 THEN 'NEUTRAL'
        WHEN distance >= -0.10 THEN 'BEARISH'
        ELSE 'BEARISH'
    END AS signal
FROM calculated
ORDER BY event_time
