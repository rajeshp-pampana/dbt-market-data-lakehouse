-- Gold: Daily market snapshot
-- One row per (isin, business_date) with USD-equivalent accepted price.
-- This is the primary downstream table consumed by reporting and analytics.

with prices as (
    select * from {{ ref('int_prices_reconciled') }}
    where recon_status in ('MATCH', 'WITHIN_TOLERANCE', 'WARNING', 'SINGLE_SOURCE')
    -- BREACH rows excluded from snapshot — routed to mart_recon_exceptions
),

instruments as (
    select * from {{ ref('int_instruments_enriched') }}
),

fx as (
    select * from {{ ref('int_fx_rates_canonical') }}
    where to_currency = 'USD'
      and quality_flag in ('OK', 'SINGLE_SOURCE')
),

-- Join prices to instrument master
with_instrument as (
    select
        p.reconciled_price_sk,
        p.isin,
        p.business_date,
        p.accepted_price,
        p.price_currency,
        p.recon_status,
        p.spread_pct,
        p.source_count,

        i.ticker,
        i.instrument_name,
        i.asset_class,
        i.asset_class_code,
        i.sector,
        i.country_code,
        i.exchange_code,
        i.native_currency,
        i.requires_fx_conversion,
        i.display_name

    from prices p
    left join instruments i using (isin)
),

-- Apply FX conversion to USD
usd_normalised as (
    select
        wi.*,

        -- FX rate: 1.0 for USD instruments, else lookup from canonical rates
        coalesce(fx.mid_rate, 1.0)           as fx_rate_to_usd,

        -- USD-equivalent accepted price
        wi.accepted_price * coalesce(fx.mid_rate, 1.0) as accepted_price_usd,

        -- FX source quality flag
        fx.quality_flag                       as fx_quality_flag

    from with_instrument wi
    left join fx
        on  wi.business_date   = fx.business_date
        and wi.native_currency = fx.from_currency
),

final as (
    select
        reconciled_price_sk,
        isin,
        business_date,
        display_name,
        instrument_name,
        asset_class,
        asset_class_code,
        sector,
        country_code,
        exchange_code,
        native_currency,
        price_currency,

        -- Prices
        accepted_price,
        accepted_price_usd,
        fx_rate_to_usd,

        -- Quality metadata
        recon_status,
        spread_pct,
        source_count,
        fx_quality_flag,

        -- Overall row quality
        case
            when recon_status = 'WARNING'       then 'YELLOW'
            when fx_quality_flag = 'SPREAD_BREACH' then 'YELLOW'
            when source_count < 2               then 'AMBER'
            else 'GREEN'
        end as row_quality_rag,

        current_timestamp as _dbt_loaded_at

    from usd_normalised
)

select * from final
