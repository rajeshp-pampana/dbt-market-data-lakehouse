-- Bronze: FX rates
-- Casts types, adds identity passthrough for USD→USD pairs.

with source as (
    select * from {{ ref('raw_fx_rates') }}
),

staged as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['business_date', 'from_currency', 'to_currency', 'source']) }} as fx_rate_sk,

        cast(rate_id      as integer)  as rate_id,
        cast(business_date as date)    as business_date,
        upper(trim(from_currency))     as from_currency,
        upper(trim(to_currency))       as to_currency,
        cast(rate         as double)   as rate,
        upper(trim(source))            as source,

        -- Derived: is this a passthrough / identity rate?
        case when from_currency = to_currency then true else false end as is_identity,

        -- Load metadata
        cast(loaded_at as timestamp)   as source_loaded_at,
        current_timestamp              as _dbt_loaded_at

    from source
)

select * from staged
