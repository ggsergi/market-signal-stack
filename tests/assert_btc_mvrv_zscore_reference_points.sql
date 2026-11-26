-- Historical reference points for int_btc_mvrv_zscore: cycle tops and
-- bottoms where the signal is known (Z in brackets, window from the first
-- available data point, checked on 2026-11-26). Same list as
-- reference_points in docs/indicator_rules/btc_mvrv_zscore.yaml (dbt does
-- not read docs/). Cross-checked against Look Into Bitcoin's cycle maxima
-- (10.53 / 10.04 / 7.13) and minima (-0.60 / -0.49 / -0.20 / -0.36).
--
-- The rule's old "~7.5 in April 2021" was mislabeled: it is the February 2021
-- peak (April 2021 is ~5). The 2021 point is 2021-02-21.
--
-- Warn, not error: Coin Metrics revises its series, so a failing point means
-- "review the data", not necessarily a broken model. Returns one row per
-- point whose signal or normalized_value differs, or that has no row.
{{ config(severity='warn') }}

WITH expected AS (
    SELECT * FROM UNNEST([
        STRUCT(DATE '2013-04-09' AS event_date, 'April 2013 top (10.65)' AS description, 'BEARISH' AS expected_signal, -1.0 AS expected_normalized_value),
        STRUCT(DATE '2015-01-14', '2015 cycle bottom (-0.60)', 'BULLISH', 1.0),
        STRUCT(DATE '2017-12-07', '2017 cycle top (10.08)', 'BEARISH', -1.0),
        STRUCT(DATE '2018-12-15', '2018 cycle bottom (-0.49)', 'BULLISH', 1.0),
        STRUCT(DATE '2020-03-12', 'COVID crash (-0.20)', 'BULLISH', 1.0),
        STRUCT(DATE '2021-02-21', 'February 2021 top (7.15)', 'BEARISH', -1.0),
        STRUCT(DATE '2022-11-09', '2022 cycle bottom (-0.36)', 'BULLISH', 1.0)
    ])
),

actual AS (
    SELECT
        DATE(event_time) AS event_date,
        mvrv_z,
        signal,
        normalized_value
    FROM {{ ref('int_btc_mvrv_zscore') }}
)

SELECT
    e.event_date,
    e.description,
    e.expected_signal,
    a.signal AS actual_signal,
    e.expected_normalized_value,
    a.normalized_value AS actual_normalized_value,
    a.mvrv_z AS actual_mvrv_z
FROM expected AS e
LEFT JOIN actual AS a USING (event_date)
WHERE a.signal IS DISTINCT FROM e.expected_signal
    OR a.normalized_value IS DISTINCT FROM e.expected_normalized_value
