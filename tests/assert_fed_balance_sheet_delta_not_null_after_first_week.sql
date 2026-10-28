SELECT *
FROM {{ ref('int_fed_balance_sheet') }}
WHERE delta IS NULL
  AND event_time != (SELECT MIN(event_time) FROM {{ ref('int_fed_balance_sheet') }})
