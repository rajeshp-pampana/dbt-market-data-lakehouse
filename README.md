# dbt Market Data Lakehouse

A production-grade **dbt + Terraform** project that implements a Bronze → Silver → Gold medallion architecture for multi-source financial market data, with Bloomberg/Reuters price reconciliation and FX normalisation.

---

## What it does

| Layer | Models | Purpose |
|-------|--------|---------|
| **Bronze** | `stg_instruments`, `stg_prices`, `stg_fx_rates` | Standardise, type-cast, quality-flag raw data |
| **Silver** | `int_instruments_enriched`, `int_prices_reconciled`, `int_fx_rates_canonical` | Reconcile Bloomberg vs Reuters prices; build canonical FX mid-rates |
| **Gold** | `mart_market_snapshot`, `mart_recon_exceptions` | USD-equivalent snapshot for all active instruments; exceptions mart for BREACH / NO_PRICE rows |

The reconciliation logic mirrors real quant-finance IPV (Independent Price Validation) workflows:

```
MATCH           → exact Bloomberg = Reuters
WITHIN_TOLERANCE → spread < 0.05 %
WARNING          → 0.05 % ≤ spread < 0.10 %
BREACH           → spread ≥ 0.10 %  → routed to mart_recon_exceptions
SINGLE_SOURCE    → only one vendor supplied a price
```

---

## Local setup (DuckDB — zero infra)

```bash
# 1. Install
pip install dbt-duckdb

# 2. Copy profile
mkdir -p ~/.dbt
cp dbt_project/profiles.yml.example ~/.dbt/profiles.yml

# 3. Install dbt packages
cd dbt_project
dbt deps

# 4. Run full pipeline
dbt seed && dbt run && dbt test

# 5. Browse docs
dbt docs generate && dbt docs serve   # http://localhost:8080
```

### Query the results

```python
import duckdb
con = duckdb.connect("dbt_project/dev.duckdb")

# Gold mart — USD-normalised snapshot
print(con.execute("SELECT * FROM gold.mart_market_snapshot").fetchdf())

# Reconciliation exceptions (BREACH + NO_PRICE)
print(con.execute("SELECT * FROM gold.mart_recon_exceptions").fetchdf())
```

---

## Infrastructure (Terraform → Azure)

Provisions:

- **Azure Resource Group** scoped to this project
- **ADLS Gen2** with hierarchical namespace; Bronze / Silver / Gold / dbt-artifacts containers
- **Service Principal** with Storage Blob Data Contributor RBAC — least-privilege, scoped to the storage account only
- **Azure Key Vault** — SP credentials stored as secrets; never in code or logs

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform plan
terraform apply
```

Set the environment variables from Terraform output before running dbt against prod:

```bash
export DATABRICKS_HOST=$(terraform output -raw databricks_host)
export DATABRICKS_HTTP_PATH=$(terraform output -raw databricks_http_path)
export DATABRICKS_TOKEN=<from Key Vault>
```

---

## CI/CD

GitHub Actions workflow (`.github/workflows/dbt_ci.yml`) runs on every push to `main` / `develop`:

1. `dbt deps`
2. `dbt seed`
3. `dbt run`
4. `dbt test`
5. `dbt docs generate`

Uses DuckDB **in-memory** (`:memory:`) — no infrastructure needed in CI.

---

## Project structure

```
dbt_project/
├── models/
│   ├── bronze/          # staging views
│   ├── silver/          # intermediate tables (reconciliation)
│   └── gold/            # business marts
├── seeds/               # sample data (instruments, prices, FX rates)
├── macros/              # generate_schema_name override
├── tests/               # custom data quality tests
└── dbt_project.yml

infra/
├── main.tf              # Terraform resources
├── variables.tf
└── outputs.tf

.github/workflows/
└── dbt_ci.yml

scripts/
└── dev_setup.sh         # one-command local setup
```

---

## Key design choices

- **DuckDB for dev/CI** — zero-cost, zero-infra; same SQL as Databricks
- **`generate_schema_name` macro** — schemas named `gold`, `silver`, `bronze` (not `main_gold` etc.)
- **Deliberate BREACH test case** — TSLA has Bloomberg 248.50 vs Reuters 249.12 (0.249% spread) so the exceptions mart always has a real row to demonstrate
- **FX normalisation** — non-USD instruments (GBP, EUR) converted to USD using canonical mid-rates; `fx_rate = 1.0` for USD instruments so the math is uniform
- **RAG quality column** — `row_quality_rag` (GREEN / YELLOW / AMBER) on every snapshot row for downstream dashboards

---

## Tech stack

`dbt-core` · `dbt-duckdb` · `dbt_utils` · `DuckDB` · `Terraform` · `Azure (ADLS Gen2, Key Vault, Service Principal)` · `GitHub Actions`
