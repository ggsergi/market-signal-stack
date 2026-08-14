WITH mart AS (
    SELECT
        event_time,
        is_dgs2_imputed,
        is_dgs10_imputed,
        ROW_NUMBER() OVER (ORDER BY event_time DESC) AS rn_desc
    FROM {{ ref('mart_yield_curve') }}
),

total_rows AS (
    SELECT COUNT(*) AS n
    FROM mart
),

first_real AS (
    SELECT
        MIN(IF(is_dgs2_imputed = FALSE, rn_desc, NULL)) AS first_real_dgs2_rn,
        MIN(IF(is_dgs10_imputed = FALSE, rn_desc, NULL)) AS first_real_dgs10_rn
    FROM mart
),

trailing_streaks AS (
    SELECT
        COALESCE(first_real.first_real_dgs2_rn, total_rows.n + 1) - 1 AS dgs2_trailing_imputed_days,
        COALESCE(first_real.first_real_dgs10_rn, total_rows.n + 1) - 1 AS dgs10_trailing_imputed_days
    FROM first_real
    CROSS JOIN total_rows
)

SELECT *
FROM trailing_streaks
WHERE dgs2_trailing_imputed_days > 5
   OR dgs10_trailing_imputed_days > 5
