{#
    Principal that gets roles/bigquery.dataViewer on the layer marts (Sara's
    agent). Used in the grants of mart_macro_global, mart_crypto_liquidity and
    mart_onchain_btc.

    Safeguard: when building into the refactor dataset it ALWAYS returns the
    placeholder, even if SARA_MARTS_READER_PRINCIPAL is set, so a refactor
    build can never grant Sara access to unvalidated tables. The grant to the
    placeholder fails ("Service account ... does not exist") and the mart is
    left in ERROR after being created: the accepted refactor workflow (tests
    run separately with dbt test --target refactor).

    Checks target.dataset, not target.name, so renaming the target in
    profiles.yml doesn't disable it.

    Outside refactor: the real principal from SARA_MARTS_READER_PRINCIPAL (not
    versioned; the repo is public), or the placeholder if it isn't set.
#}
{% macro sara_marts_reader() %}
    {%- set placeholder = 'serviceAccount:sara-marts-reader@your-gcp-project.iam.gserviceaccount.com' -%}
    {%- if target.dataset == 'market_signal_marts_refactor' -%}
        {{ return(placeholder) }}
    {%- endif -%}
    {{ return(env_var('SARA_MARTS_READER_PRINCIPAL', placeholder)) }}
{% endmacro %}
