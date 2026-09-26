-- Gold: Reconciliation exceptions
-- Surfaces BREACH-status prices and instruments with no reconciled price.
-- Fed to a downstream alerting / manual-review workflow.

with prices as (
    select * from {{ ref('int_prices_reconciled') }}
),

instruments as (
    select * from {{ ref('int_instruments_enriched') }}
),

-- Breached price pairs
breaches as (
    select
        p.isin,
        p.business_date,
        p.bloomberg_price,
        p.reuters_price,
        p.price_diff,
        p.spread_pct,
        p.recon_status,
        'PRICE_BREACH' as exception_type,
        'Bloomberg vs Reuters spread >= 0.10%' as exception_detail

    from prices p
    where p.recon_status = 'BREACH'
),

-- Active instruments with no price for any available business date
-- (uses the latest business date from the price feed)
missing_prices as (
    select distinct
        i.isin,
        cast((select max(business_date) from prices) as date) as business_date,
        null::double as bloomberg_price,
        null::double as reuters_price,
        null::double as price_diff,
        null::double as spread_pct,
        'NO_PRICE' as recon_status,
        'NO_PRICE' as exception_type,
        'No price received for latest business date' as exception_detail

    from instruments i
    where not exists (
        select 1 from prices p
        where p.isin = i.isin
    )
),

all_exceptions as (
    select * from breaches
    union all
    select * from missing_prices
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['isin', 'business_date', 'exception_type']) }} as exception_sk,

        e.*,

        i.instrument_name,
        i.asset_class,
        i.sector,
        i.display_name,
        i.native_currency,

        current_timestamp as _dbt_loaded_at

    from all_exceptions e
    left join instruments i using (isin)
)

select * from final
order by exception_type, spread_pct desc nulls last
