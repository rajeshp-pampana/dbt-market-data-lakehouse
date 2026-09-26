-- Bronze: Instruments reference data
-- Casts raw seed types, adds a surrogate key, preserves all source columns.
-- Materialized as VIEW — zero storage cost; recomputed on demand.

with source as (
    select * from {{ ref('raw_instruments') }}
),

staged as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['isin']) }} as instrument_sk,

        -- Natural key
        trim(isin)    as isin,
        trim(ticker)  as ticker,

        -- Descriptive attributes
        trim(name)        as instrument_name,
        upper(trim(asset_class)) as asset_class,
        upper(trim(currency))    as native_currency,
        upper(trim(exchange))    as exchange_code,
        upper(trim(country))     as country_code,
        trim(sector)             as sector,

        -- Status
        cast(is_active as boolean) as is_active,

        -- Audit
        cast(created_at as date) as source_created_date,

        -- Load metadata
        current_timestamp as _dbt_loaded_at

    from source
)

select * from staged
