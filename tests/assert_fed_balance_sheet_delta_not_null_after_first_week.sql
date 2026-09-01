SELECT *
FROM {{ ref('mart_fed_balance_sheet') }}
WHERE delta IS NULL
  AND event_time != (SELECT MIN(event_time) FROM {{ ref('mart_fed_balance_sheet') }})
