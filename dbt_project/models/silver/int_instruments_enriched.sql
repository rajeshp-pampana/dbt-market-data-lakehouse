-- Silver: Enriched instrument master
-- Filters to active instruments only, classifies asset types, adds display labels.

with instruments as (
    select * from {{ ref('stg_instruments') }}
),

enriched as (
    select
        instrument_sk,
        isin,
        ticker,
        instrument_name,
        asset_class,
        native_currency,
        exchange_code,
        country_code,
        sector,
        is_active,
        source_created_date,

        -- Derived classification
        case asset_class
            when 'EQUITY'       then 'EQ'
            when 'FIXED_INCOME' then 'FI'
            when 'COMMODITY'    then 'CM'
            when 'FX'           then 'FX'
            else 'OT'
        end as asset_class_code,

        -- Display label used in Gold reports
        coalesce(ticker, isin) as display_name,

        -- Flag instruments that price in a non-USD currency
        -- (need FX conversion in downstream models)
        case when native_currency != 'USD' then true else false end as requires_fx_conversion,

        _dbt_loaded_at

    from instruments
    where is_active = true  -- drop delisted instruments at Silver layer
)

select * from enriched
