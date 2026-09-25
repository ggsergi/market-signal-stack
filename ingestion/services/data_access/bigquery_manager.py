"""BigQuery connector.

Mirrors the role of database_manager.py in the_trimarket_crew, but synchronous:
asyncpg forced async/await, whereas the BigQuery client is synchronous and what
blocks is waiting for a job to finish. Keeping asyncio here would buy nothing and
cost boilerplate in every script.

This module knows nothing about FRED, Binance or any other provider. Adding a new
source must never require a change here -- that is what keeps the raw layer generic
instead of generic-on-paper.
"""

import glob
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path

from google.cloud import bigquery
from google.oauth2 import service_account

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]


class BigQueryError(RuntimeError):
    """Wrapper exception for BigQuery failures."""


def project_id_from_env() -> str:
    """Read the GCP project id from GCP_PROJECT_ID.

    Not hardcoded: the repo is public and the real project id is kept out of it.
    """
    project_id = os.environ.get("GCP_PROJECT_ID", "").strip()
    if not project_id:
        raise BigQueryError("GCP_PROJECT_ID is not set. Export it before running.")
    return project_id


@dataclass(slots=True)
class BigQueryConfig:
    """Connection settings.

    Deliberately not a YAML file: unlike Postgres there is no host, port, user or
    password to configure. Credentials already live in the service account JSON,
    and the rest is three constants.
    """

    project_id: str = field(default_factory=project_id_from_env)
    raw_dataset: str = "raw_market_signals"
    marts_dataset: str = "market_signal_marts"
    credentials_path: str | None = None

    @classmethod
    def from_defaults(cls) -> "BigQueryConfig":
        return cls(credentials_path=find_key_file())


def find_key_file() -> str | None:
    """Locate a service account JSON key, honoring the env var then ./config."""
    env_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if env_path and os.path.isfile(env_path):
        return env_path

    matches = sorted(glob.glob(str(REPO_ROOT / "config" / "*.json")))
    return matches[0] if matches else None


class BigQueryManager:
    """Thin transport layer: run queries, load rows, inspect tables."""

    def __init__(self, config: BigQueryConfig | None = None):
        self.config = config or BigQueryConfig.from_defaults()
        self._client: bigquery.Client | None = None

    # -----------------------------
    # Connection
    # -----------------------------

    @property
    def client(self) -> bigquery.Client:
        """Lazily build the client so importing this module never hits the network."""
        if self._client is not None:
            return self._client

        key_file = self.config.credentials_path or find_key_file()
        if not key_file:
            raise BigQueryError(
                "No service account key found. Put a *.json key in ./config "
                "or set GOOGLE_APPLICATION_CREDENTIALS."
            )

        credentials = service_account.Credentials.from_service_account_file(key_file)

        # Asserted, not inferred: pointing a key at the wrong project would create
        # tables that look correct and are invisible to everyone else on the team.
        if credentials.project_id != self.config.project_id:
            raise BigQueryError(
                f"Credentials point to project {credentials.project_id!r}, "
                f"expected {self.config.project_id!r}."
            )

        self._client = bigquery.Client(
            credentials=credentials, project=self.config.project_id
        )
        return self._client

    # -----------------------------
    # Table references
    # -----------------------------

    def raw(self, table_name: str) -> str:
        """Fully qualified id of a table in the raw dataset."""
        return f"{self.config.project_id}.{self.config.raw_dataset}.{table_name}"

    def mart(self, table_name: str) -> str:
        """Fully qualified id of a table or view in the marts dataset."""
        return f"{self.config.project_id}.{self.config.marts_dataset}.{table_name}"

    def get_table(self, table_id: str) -> bigquery.Table:
        return self.client.get_table(table_id)

    def table_exists(self, table_id: str) -> bool:
        from google.api_core.exceptions import NotFound

        try:
            self.client.get_table(table_id)
            return True
        except NotFound:
            return False

    def drop_table(self, table_id: str) -> None:
        """Delete a table, tolerating its absence.

        not_found_ok because the only caller cleans up scratch tables: a run that
        died before creating one must not fail on the way out.
        """
        self.client.delete_table(table_id, not_found_ok=True)

    # -----------------------------
    # Queries
    # -----------------------------

    @staticmethod
    def _build_params(params: dict | None):
        """Turn a plain dict into BigQuery scalar query parameters.

        Query parameters are not cosmetic here: they are what stops a value from
        being concatenated into SQL, and they preserve TIMESTAMP typing.
        """
        if not params:
            return []

        from datetime import date, datetime

        type_map = {
            str: "STRING",
            int: "INT64",
            float: "FLOAT64",
            bool: "BOOL",
            datetime: "TIMESTAMP",
            date: "DATE",
        }

        built = []
        for name, value in params.items():
            bq_type = type_map.get(type(value))
            if bq_type is None:
                raise BigQueryError(
                    f"Unsupported parameter type for {name!r}: {type(value).__name__}"
                )
            built.append(bigquery.ScalarQueryParameter(name, bq_type, value))
        return built

    def execute(self, sql: str, params: dict | None = None):
        """Run a statement and wait for completion. Returns the job."""
        try:
            job_config = bigquery.QueryJobConfig(
                query_parameters=self._build_params(params)
            )
            job = self.client.query(sql, job_config=job_config)
            job.result()
            return job
        except Exception as exc:
            logger.exception("BigQuery execute failed")
            raise BigQueryError(f"BigQuery execute failed: {exc}") from exc

    def fetch(self, sql: str, params: dict | None = None) -> list:
        """Run a query and return all rows."""
        try:
            job_config = bigquery.QueryJobConfig(
                query_parameters=self._build_params(params)
            )
            return list(self.client.query(sql, job_config=job_config).result())
        except Exception as exc:
            logger.exception("BigQuery fetch failed")
            raise BigQueryError(f"BigQuery fetch failed: {exc}") from exc

    def fetchval(self, sql: str, params: dict | None = None):
        """Run a query and return the first column of the first row, or None."""
        rows = self.fetch(sql, params)
        return rows[0][0] if rows else None

    # -----------------------------
    # Loading
    # -----------------------------

    def load_rows(
        self,
        rows: list[dict],
        table_id: str,
        schema: list,
        write_disposition: str = "WRITE_APPEND",
    ) -> int:
        """Load rows through a load job. Returns the number of rows written.

        Always a load job, never insert_rows_json(): load jobs are free and allow
        reprocessing, while streaming inserts are billed and their buffer blocks DML
        on the table for roughly 90 minutes.
        """
        if not rows:
            return 0

        try:
            job_config = bigquery.LoadJobConfig(
                schema=schema,
                source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
                write_disposition=write_disposition,
            )
            job = self.client.load_table_from_json(
                rows, table_id, job_config=job_config
            )
            job.result()
            return job.output_rows or 0
        except Exception as exc:
            logger.exception("BigQuery load failed for %s", table_id)
            raise BigQueryError(f"BigQuery load failed for {table_id}: {exc}") from exc
