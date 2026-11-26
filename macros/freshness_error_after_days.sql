{#
    Devuelve, en días, el error_after del bloque de freshness `source_table_name`
    de _sources.yml (raw_market_metrics, raw_market_metrics_weekly o
    raw_market_metrics_monthly). Lo usan los marts de capa como caducidad del
    arrastre as-of, para que la política de "dato demasiado viejo" tenga una
    única fuente de verdad junto a la de source freshness.

    En parse (execute = false) graph aún no está poblado: devuelve 0, que no se
    usa porque el SQL solo se ejecuta tras compilar con execute = true.
#}
{% macro freshness_error_after_days(source_table_name) %}
    {%- if not execute -%}
        {{ return(0) }}
    {%- endif -%}
    {%- set days_per_period = {'minute': 1 / 1440, 'hour': 1 / 24, 'day': 1} -%}
    {%- for node in graph.sources.values()
        if node.source_name == 'market_signal_stack' and node.name == source_table_name -%}
        {%- set error_after = node.freshness.error_after if node.freshness else none -%}
        {%- if not error_after or not error_after.count -%}
            {{ exceptions.raise_compiler_error("freshness_error_after_days: " ~ source_table_name ~ " no tiene error_after en _sources.yml") }}
        {%- endif -%}
        {{ return(error_after.count * days_per_period[error_after.period]) }}
    {%- endfor -%}
    {{ exceptions.raise_compiler_error("freshness_error_after_days: no existe el source " ~ source_table_name) }}
{% endmacro %}
