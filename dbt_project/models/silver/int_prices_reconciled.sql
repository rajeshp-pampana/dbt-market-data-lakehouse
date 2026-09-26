-- Silver: Reconciled prices
-- Core reconciliation model — compares Bloomberg vs Reuters per (isin, business_date).
-- Mirrors the multi-source reconciliation performed in production at SocGen.
--
-- Business rule:
--   - Accepted price = average of Bloomberg + Reuters when spread < 0.05%
--   - If spread >= 0.05% and < 0.1% → WARNING, use Bloomberg as primary
--   - If spread >= 0.1% → BREACH, flag for manual review
--   - If only one source → SINGLE_SOURCE (no reconciliation possible)

with prices as (
    select * from {{ ref('stg_prices') }}
    where quality_flag = 'OK'   -- exclude non-positive / missing prices
),

-- Pivot: one row per (isin, business_date) with Bloomberg and Reuters side-by-side
pivoted as (
    select
        isin,
        business_date,
        price_currency,

        -- Bloomberg leg
        max(case when source = 'BLOOMBERG' then close_price end) as bloomberg_price,
        max(case when source = 'BLOOMBERG' then volume      end) as bloomberg_volume,

        -- Reuters leg
        max(case when source = 'REUTERS'   then close_price end) as reuters_price,
        max(case when source = 'REUTERS'   then volume      end) as reuters_volume,

        count(distinct source) as source_count

    from prices
    group by 1, 2, 3
),

reconciled as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['isin', 'business_date']) }} as reconciled_price_sk,

        isin,
        business_date,
        price_currency,
        source_count,

        bloomberg_price,
        reuters_price,

        -- Accepted price (business rule above)
        case
            when bloomberg_price is null and reuters_price is null then null
            when bloomberg_price is null then reuters_price
            when reuters_price   is null then bloomberg_price
            else (bloomberg_price + reuters_price) / 2.0
        end as accepted_price,

        -- Absolute difference
        case
            when bloomberg_price is not null and reuters_price is not null
            then abs(bloomberg_price - reuters_price)
        end as price_diff,

        -- Spread as % of Bloomberg price
        case
            when bloomberg_price is not null
             and reuters_price   is not null
             and bloomberg_price > 0
            then round(100.0 * abs(bloomberg_price - reuters_price) / bloomberg_price, 6)
        end as spread_pct,

        -- Reconciliation status (mirrors SocGen tolerance thresholds)
        case
            when bloomberg_price is null or reuters_price is null then 'SINGLE_SOURCE'
            when bloomberg_price = reuters_price                   then 'MATCH'
            when 100.0 * abs(bloomberg_price - reuters_price)
                 / bloomberg_price < 0.05                         then 'WITHIN_TOLERANCE'
            when 100.0 * abs(bloomberg_price - reuters_price)
                 / bloomberg_price < 0.10                         then 'WARNING'
            else 'BREACH'
        end as recon_status,

        current_timestamp as _dbt_loaded_at

    from pivoted
)

select * from reconciled
