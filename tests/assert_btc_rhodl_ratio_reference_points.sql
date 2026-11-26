-- Reference points for int_btc_rhodl_ratio inside the BGeometrics window
-- (from 2022-11-26). Values checked in the refactor build on 2026-11-26
-- (RHODL in brackets). Same list as reference_points in
-- docs/indicator_rules/rhodl_ratio_btc.yaml (dbt does not read docs/).
--
-- The 2024 high stays at -0.6, not -1.0: cycle tops decline each cycle
-- (documented limitation of the provisional bands).
--
-- Warn, not error: the bands are provisional and the series comes from a free
-- plan, so a failing point means "review", not necessarily a broken model.
{{ config(severity='warn') }}

WITH expected AS (
    SELECT * FROM UNNEST([
        STRUCT(DATE '2022-12-26' AS event_date, 'end-2022 bottom (202)' AS description, 'BULLISH' AS expected_signal, 1.0 AS expected_normalized_value),
        STRUCT(DATE '2024-12-10', '2024 high (13,730)', 'BEARISH', -0.6)
    ])
),

actual AS (
    SELECT
        DATE(event_time) AS event_date,
        rhodl,
        signal,
        normalized_value
    FROM {{ ref('int_btc_rhodl_ratio') }}
)

SELECT
    e.event_date,
    e.description,
    e.expected_signal,
    a.signal AS actual_signal,
    e.expected_normalized_value,
    a.normalized_value AS actual_normalized_value,
    a.rhodl AS actual_rhodl
FROM expected AS e
LEFT JOIN actual AS a USING (event_date)
WHERE a.signal IS DISTINCT FROM e.expected_signal
    OR a.normalized_value IS DISTINCT FROM e.expected_normalized_value
