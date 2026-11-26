{#
    Devuelve, como texto decimal (p. ej. '1.1'), el meta.weight del modelo
    `model_name` (un int_<indicador>). Ese valor es copia exacta del weight de
    su regla en docs/indicator_rules/, que es la fuente de verdad; dbt no lee
    docs/, así que el peso que usa el cálculo de capa vive en el meta del modelo.

    Falla al compilar si el modelo no existe o no tiene meta.weight numérico:
    un indicador sin peso no debe desaparecer en silencio del layer_score.

    En parse (execute = false) graph aún no está poblado: devuelve '0', que no
    se usa porque el SQL solo se ejecuta tras compilar con execute = true.
#}
{% macro indicator_weight(model_name) %}
    {%- if not execute -%}
        {{ return('0') }}
    {%- endif -%}
    {%- set node = graph.nodes.get('model.' ~ project_name ~ '.' ~ model_name) -%}
    {%- if node is none -%}
        {{ exceptions.raise_compiler_error("indicator_weight: no existe el modelo " ~ model_name) }}
    {%- endif -%}
    {%- set weight = (node.config.meta or {}).get('weight') -%}
    {%- if weight is none or weight is string or weight is boolean -%}
        {{ exceptions.raise_compiler_error("indicator_weight: " ~ model_name ~ " no tiene meta.weight numérico (valor: " ~ weight ~ ")") }}
    {%- endif -%}
    {{ return(weight | string) }}
{% endmacro %}
