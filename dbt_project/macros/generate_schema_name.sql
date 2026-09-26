{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Override dbt's default schema naming.

        Default behaviour:  main_gold, main_silver, main_bronze
        This macro gives:   gold, silver, bronze  (or raw for seeds)

        In prod (Databricks) the catalog + schema from profiles.yml still apply;
        this only affects local DuckDB dev/CI targets where the default target
        schema is 'main' and we want clean, bare schema names.
    #}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
