"""SQL statements as constants.

Table ids are injected with .format() because BigQuery does not accept query
parameters for table names. The ids come from BigQueryManager constants, never from
user input, so there is nothing to inject. Actual values always travel as query
parameters.
"""


class QueryStrs:
    # -----------------------------------------------------------------
    # raw_market_metrics -- upsert
    # -----------------------------------------------------------------
    # Natural key: source + metric + COALESCE(asset) + COALESCE(timeframe) + event_time
    #
    # The COALESCE around asset and timeframe is not cosmetic. In SQL, NULL = NULL
    # evaluates to NULL rather than TRUE, so a plain equality never matches on global
    # metrics (yield_10y, cpi_yoy, fear_greed) and every run would silently insert
    # duplicates.
    #
    # The event_time lower bound prunes partitions: without it the MERGE scans the
    # entire table on every run.
    #
    # WHEN MATCHED updates rather than skipping, so source revisions are absorbed for
    # free. Irrelevant for Treasury yields, critical once CPI arrives.
    #
    # The update is conditional on something having changed. Not the payload: FRED
    # stamps realtime_start/realtime_end with the query date, so it differs on every
    # run and would rewrite the whole window each time. Skipping unchanged rows also
    # keeps ingested_at meaning "when this value was first captured".
    MERGE_MARKET_METRICS = """
    MERGE `{target}` T
    USING `{staging}` S
      ON  T.source = S.source
      AND T.metric = S.metric
      AND COALESCE(T.asset, '')     = COALESCE(S.asset, '')
      AND COALESCE(T.timeframe, '') = COALESCE(S.timeframe, '')
      AND T.event_time = S.event_time
      AND T.event_time >= @min_event_time
    WHEN MATCHED AND (
         T.value         != S.value
      OR T.unit          != S.unit
      OR T.market_type   != S.market_type
      OR T.metric_family != S.metric_family
    ) THEN UPDATE SET
      market_type   = S.market_type,
      metric_family = S.metric_family,
      value         = S.value,
      unit          = S.unit,
      payload       = S.payload,
      ingested_at   = S.ingested_at
    WHEN NOT MATCHED THEN INSERT ROW
    """
