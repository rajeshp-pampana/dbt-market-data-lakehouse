-- Bronze: Daily market prices
-- Casts types, normalises source names, adds quality flags.
-- One row per (isin, business_date, source) — duplicates handled downstream.

with source as (
    select * from {{ ref('raw_prices') }}
),

staged as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['isin', 'business_date', 'source']) }} as price_sk,

        -- Natural key components
        cast(price_id     as integer)  as price_id,
        trim(isin)                     as isin,
        cast(business_date as date)    as business_date,
        upper(trim(source))            as source,

        -- Price fields — null-safe casts
        cast(close_price as double)    as close_price,
        cast(open_price  as double)    as open_price,
        cast(high_price  as double)    as high_price,
        cast(low_price   as double)    as low_price,
        cast(volume      as bigint)    as volume,

        upper(trim(currency))          as price_currency,

        -- Data quality flag: prices must be positive
        case
            when close_price is null         then 'MISSING_CLOSE'
            when cast(close_price as double) <= 0 then 'NON_POSITIVE_PRICE'
            else 'OK'
        end as quality_flag,

        -- Load metadata
        cast(loaded_at as timestamp)   as source_loaded_at,
        current_timestamp              as _dbt_loaded_at

    from source
)

select * from staged
