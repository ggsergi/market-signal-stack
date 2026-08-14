WITH raw_signals AS (
    SELECT * FROM {{ source('market_signal_stack', 'raw_market_metrics') }}
)

SELECT
    source,
    market_type,
    asset,
    metric,
    metric_family,
    SAFE_CAST(value AS FLOAT64) AS value,
    unit,
    timeframe,
    SAFE_CAST(event_time AS TIMESTAMP) AS event_time
FROM raw_signals
