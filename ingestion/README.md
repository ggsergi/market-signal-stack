# Ingestion

Downloads market and macro data from FRED and Yahoo Finance and lands it in
BigQuery, in `raw_market_signals.raw_market_metrics`. That table is the source the
dbt project in the repo root reads from.

```
FRED / Yahoo Finance ──▶ raw_market_signals.raw_market_metrics ──▶ dbt (models/)
```

## Setup

Dependencies are managed by `uv` from the repo root (`pyproject.toml`).

Credentials are never committed. Before running:

| What | How |
|------|-----|
| GCP project | `GCP_PROJECT_ID` environment variable. Must match the project of the service account key. |
| BigQuery credentials | A service account JSON key in `ingestion/config/`, or its path in `GOOGLE_APPLICATION_CREDENTIALS`. |
| FRED API key | `FRED_API_KEY` environment variable, or the key in `ingestion/config/fred_api_key.txt`. Free at https://fredaccount.stlouisfed.org/apikeys |

All commands below run from the `ingestion/` directory.

## Check the connection

```bash
uv run python test_bigquery_connection.py
```

Runs a test query and lists the datasets the account can see.

## Load data

```bash
# Preview: shows what would be loaded, writes nothing
uv run python scripts/run_jobs.py

# Write to BigQuery
uv run python scripts/run_jobs.py --persist
```

Without flags, a run covers the last 30 days (`settings.incremental_window_days` in
`config/sources.yaml`).

Re-running any window is safe: writes go through a `MERGE` on the natural key, so new
observations are inserted, values revised by the source are updated, and everything
else is left untouched.

| Flag | Effect |
|------|--------|
| `--persist` | Write to BigQuery. Without it the run is a dry preview. |
| `--days N` | Last N days, ending today. `--days 1` = today only. |
| `--start-date YYYY-MM-DD` | Explicit start date. |
| `--end-date YYYY-MM-DD` | Explicit end date. Defaults to today. |
| `--backfill` | Full history, from each indicator's `backfill_start_date`. |
| `--indicator NAME` | Only that indicator. Repeatable. |

If one source fails, the others are still loaded and the failure is logged.

## Indicators

Defined in `config/sources.yaml`:

| Indicator (`--indicator`) | Metric in the raw table | Source | Series / ticker | Frequency |
|---|---|---|---|---|
| `yield_2y` | `yield_2y` | FRED | `DGS2` | daily |
| `yield_10y` | `yield_10y` | FRED | `DGS10` | daily |
| `fed_liquidity` | `fed_liquidity` | FRED | `WALCL` | weekly |
| `m2_usa` | `m2_usa` | FRED | `M2SL` | monthly |
| `spx_index` | `spx` | Yahoo Finance | `^GSPC` | daily |
| `ndx_index` | `ndx` | Yahoo Finance | `^NDX` | daily |
| `dxy_index` | `dxy` | Yahoo Finance | `^NYICDX` | daily |
| `vix_index` | `vix` | Yahoo Finance | `^VIX` | daily |
| `move_index` | `move` | Yahoo Finance | `^MOVE` | daily |
| `btc_price` | `btc_price` | Yahoo Finance | `BTC-USD` | daily |

### Adding an indicator

1. Add an entry under `indicators:` in `config/sources.yaml`. No new table or schema
   change is needed: every metric lands in the same long-format table.
2. If it uses a new `source`, `market_type`, `metric_family` or `unit`, add it to
   `services/vocab.py` first. Rows with values outside that vocabulary are rejected.
3. If it is daily, also add it to the `freshness.filter` list in
   `models/staging/_sources.yml`.

## Raw table conventions

- One row = one metric, from one source, at one instant (long format).
- `asset` is `NULL` for global metrics (yields, M2...), never an empty string.
- `event_time` is UTC. Sources that only give a date are anchored to `00:00:00Z`.
- `value` is stored exactly as the source delivers it: no rounding, no unit conversion.
- `payload` keeps the original JSON of that observation.

## Layout

```
ingestion/
├── config/sources.yaml          what gets ingested
├── scripts/run_jobs.py          entry point
├── services/
│   ├── etl_pipeline/
│   │   ├── sources/api/         FRED and Yahoo Finance loaders
│   │   ├── transforms/          loader output -> raw table rows
│   │   ├── jobs/                the refresh job (CLI)
│   │   └── loader_factory.py    builds loaders from sources.yaml
│   ├── data_access/             BigQuery client, MERGE upsert
│   └── vocab.py                 allowed values for the raw table
└── test_bigquery_connection.py
```
