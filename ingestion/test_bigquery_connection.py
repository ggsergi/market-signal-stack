"""Test connectivity to Google Cloud BigQuery.

Usage:
    python test_bigquery_connection.py

Uses the service account key in ./config by default. Override with:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json python test_bigquery_connection.py
"""

import glob
import os
import sys

from google.cloud import bigquery
from google.oauth2 import service_account


def find_key_file() -> str | None:
    """Locate a service account JSON key, honoring env var then ./config."""
    env_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if env_path and os.path.isfile(env_path):
        return env_path

    config_dir = os.path.join(os.path.dirname(__file__), "config")
    matches = sorted(glob.glob(os.path.join(config_dir, "*.json")))
    return matches[0] if matches else None


def main() -> int:
    key_file = find_key_file()
    if not key_file:
        print("ERROR: No service account key found.")
        print("       Put a *.json key in ./config or set GOOGLE_APPLICATION_CREDENTIALS.")
        return 1

    print(f"Using credentials: {key_file}")
    credentials = service_account.Credentials.from_service_account_file(key_file)
    project = credentials.project_id
    print(f"Project: {project}")

    client = bigquery.Client(credentials=credentials, project=project)

    # 1. A trivial query proves auth + query API reachability.
    print("\nRunning test query...")
    result = list(client.query("SELECT 1 AS ok, CURRENT_TIMESTAMP() AS ts").result())
    row = result[0]
    print(f"  -> ok={row.ok}, server_time={row.ts}")

    # 2. List datasets to confirm the account can see project resources.
    print("\nDatasets visible to this account:")
    datasets = list(client.list_datasets())
    if datasets:
        for ds in datasets:
            print(f"  - {ds.dataset_id}")
    else:
        print("  (none — connection works, but no datasets or no list permission)")

    print("\nSUCCESS: Connected to BigQuery.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - surface any failure clearly
        print(f"\nFAILED: {type(exc).__name__}: {exc}")
        sys.exit(1)
