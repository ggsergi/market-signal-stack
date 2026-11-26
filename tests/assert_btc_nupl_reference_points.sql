-- Historical reference points for int_btc_nupl: cycle tops and bottoms where
-- the signal is known. Copied from reference_points in
-- docs/indicator_rules/btc_nupl_cycle_regime.yaml (dbt does not read docs/).
--
-- Warn, not error: Coin Metrics revises its series, so a failing point means
-- "review the data", not necessarily a broken model. Returns one row per
-- point whose signal or normalized_value differs, or that has no row.
{{ config(severity='warn') }}

WITH expected AS (
    SELECT * FROM UNNEST([
        STRUCT(DATE '2013-12-04' AS event_date, '2013 cycle top' AS description, 'BEARISH' AS expected_signal, -1.0 AS expected_normalized_value),
        STRUCT(DATE '2015-01-14', '2015 cycle bottom', 'BULLISH', 1.0),
        STRUCT(DATE '2017-12-17', '2017 cycle top', 'BEARISH', -1.0),
        STRUCT(DATE '2018-12-15', '2018 cycle bottom', 'BULLISH', 1.0),
        STRUCT(DATE '2020-03-12', 'COVID crash', 'BULLISH', 1.0),
        STRUCT(DATE '2021-03-13', 'first 2021 top', 'BEARISH', -1.0),
        STRUCT(DATE '2021-11-10', 'second, lower 2021 top', 'BEARISH', -0.6),
        STRUCT(DATE '2022-11-21', '2022 cycle bottom', 'BULLISH', 1.0)
    ])
),

actual AS (
    SELECT
        DATE(event_time) AS event_date,
        nupl,
        signal,
        normalized_value
    FROM {{ ref('int_btc_nupl') }}
)

SELECT
    e.event_date,
    e.description,
    e.expected_signal,
    a.signal AS actual_signal,
    e.expected_normalized_value,
    a.normalized_value AS actual_normalized_value,
    a.nupl AS actual_nupl
FROM expected AS e
LEFT JOIN actual AS a USING (event_date)
WHERE a.signal IS DISTINCT FROM e.expected_signal
    OR a.normalized_value IS DISTINCT FROM e.expected_normalized_value
