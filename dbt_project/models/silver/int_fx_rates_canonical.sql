-- Silver: Canonical FX rates
-- One rate per (business_date, from_currency, to_currency) — averaged across sources.
-- Validates that Bloomberg and Reuters are within 0.1% of each other.

with fx as (
    select * from {{ ref('stg_fx_rates') }}
),

-- Average across sources to get a single canonical mid-rate
canonical as (
    select
        business_date,
        from_currency,
        to_currency,

        avg(rate)               as mid_rate,
        min(rate)               as min_rate,
        max(rate)               as max_rate,
        count(distinct source)  as source_count,

        -- Spread between sources as a % of the mid — a reconciliation signal
        case
            when avg(rate) = 0 then null
            else round(100.0 * (max(rate) - min(rate)) / avg(rate), 4)
        end as source_spread_pct,

        -- Quality flag: if spread > 0.1% flag for review
        case
            when count(distinct source) = 1 then 'SINGLE_SOURCE'
            when avg(rate) = 0             then 'ZERO_RATE'
            when 100.0 * (max(rate) - min(rate)) / avg(rate) > 0.1
                then 'SPREAD_BREACH'
            else 'OK'
        end as quality_flag,

        current_timestamp as _dbt_loaded_at

    from fx
    where rate > 0  -- exclude zero rates from average
    group by 1, 2, 3
)

select * from canonical
