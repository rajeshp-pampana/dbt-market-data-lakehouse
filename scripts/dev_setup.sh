#!/usr/bin/env bash
# dev_setup.sh — one-command local development setup
set -euo pipefail

echo "==> Installing dbt-duckdb..."
pip install dbt-duckdb

echo "==> Copying profiles template..."
if [ ! -f ~/.dbt/profiles.yml ]; then
  mkdir -p ~/.dbt
  cp "$(dirname "$0")/../dbt_project/profiles.yml.example" ~/.dbt/profiles.yml
  echo "    Created ~/.dbt/profiles.yml (edit if needed)"
else
  echo "    ~/.dbt/profiles.yml already exists — skipping"
fi

echo "==> Installing dbt packages..."
cd "$(dirname "$0")/../dbt_project"
dbt deps

echo "==> Running pipeline: seed → run → test..."
dbt seed
dbt run
dbt test

echo ""
echo "✓  Setup complete. DuckDB database: dbt_project/dev.duckdb"
echo ""
echo "Next steps:"
echo "  dbt docs generate && dbt docs serve   # browse docs at http://localhost:8080"
echo "  python -c \"import duckdb; print(duckdb.connect('dev.duckdb').execute('SELECT * FROM gold.mart_market_snapshot').df())\""
