#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'USAGE'
Usage: gcp-costs [--days N] [--month YYYY-MM] [--start YYYY-MM-DD] [--end YYYY-MM-DD]

Shows Google Cloud costs aggregated by project and in total for the selected period.

Requires an existing Cloud Billing BigQuery export table. Set env var:
  BILLING_EXPORT_TABLE="<project>.<dataset>.<table>"  # e.g., my-bill-proj.billing.gcp_billing_export_v1_01234ABC

Date selection (choose one):
  --days N         Last N days (default: 30)
  --month YYYY-MM  Calendar month (e.g., 2025-08)
  --start YYYY-MM-DD --end YYYY-MM-DD  Custom inclusive-exclusive range [start, end)

Examples:
  BILLING_EXPORT_TABLE="my-proj.billing.gcp_billing_export_v1_ABC" gcp-costs --month 2025-08
  gcp-costs --days 7
USAGE
}

if ! command -v bq >/dev/null 2>&1; then
  echo "Error: 'bq' CLI not found. Ensure google-cloud-sdk is installed in the shell." >&2
  exit 2
fi

TABLE="${BILLING_EXPORT_TABLE:-}"
if [[ -z $TABLE && -n ${GOOGLE_BILLING_EXPORT:-} ]]; then
  TABLE="$GOOGLE_BILLING_EXPORT"
fi
if [[ -z $TABLE ]]; then
  echo "Error: BILLING_EXPORT_TABLE environment variable is not set." >&2
  echo 'Hint: export BILLING_EXPORT_TABLE="<project>.<dataset>.<table>"' >&2
  echo >&2
  show_help
  exit 1
fi

DAYS=30
START=""
END=""
MONTH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    show_help
    exit 0
    ;;
  --days)
    DAYS="$2"
    shift 2
    ;;
  --month)
    MONTH="$2"
    shift 2
    ;;
  --start)
    START="$2"
    shift 2
    ;;
  --end)
    END="$2"
    shift 2
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo
    show_help
    exit 1
    ;;
  esac
done

if [[ -n $MONTH ]]; then
  if date -u -d "$MONTH-01" "+%Y-%m" >/dev/null 2>&1; then
    START=$(date -u -d "$MONTH-01" +%Y-%m-01T00:00:00Z)
    END=$(date -u -d "$MONTH-01 +1 month" +%Y-%m-01T00:00:00Z)
  else
    START=$(date -u -j -f "%Y-%m-%d" "$MONTH-01" +%Y-%m-01T00:00:00Z) || {
      echo "Invalid --month format, expected YYYY-MM" >&2
      exit 1
    }
    END=$(date -u -j -v+1m -f "%Y-%m-%d" "$MONTH-01" +%Y-%m-01T00:00:00Z)
  fi
fi

if [[ -n $START && -z $END ]]; then
  echo "Error: --start provided without --end" >&2
  exit 1
fi
if [[ -z $START && -n $END ]]; then
  echo "Error: --end provided without --start" >&2
  exit 1
fi

if [[ -z $START && -z $END ]]; then
  if date -u -d "@$(($(date -u +%s) - (DAYS * 24 * 3600)))" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    START=$(date -u -d "@$(($(date -u +%s) - (DAYS * 24 * 3600)))" +%Y-%m-%dT%H:%M:%SZ)
    END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  else
    START=$(date -u -v-"$DAYS"d +%Y-%m-%dT%H:%M:%SZ)
    END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fi
fi

echo "🔎 Querying billing export table: $TABLE"
echo "   Period: [$START .. $END)"

SQL="
WITH expanded AS (
    SELECT
    CAST(project.id AS STRING) AS project_id,
    cost,
    (SELECT SUM(c.amount) FROM UNNEST(credits) c) AS credit_sum
    FROM \`$TABLE\`
    WHERE usage_start_time >= TIMESTAMP('$START')
    AND usage_end_time   <  TIMESTAMP('$END')
),
by_project AS (
    SELECT project_id, ROUND(SUM(cost + IFNULL(credit_sum, 0)), 2) AS project_cost
    FROM expanded
    GROUP BY project_id
)
SELECT * FROM by_project ORDER BY project_cost DESC
"

bq --quiet query --nouse_legacy_sql --format=csv "$SQL" |
  awk -F, 'NR==1{print; next} {printf "%s,%.2f\n", $1, $2}' |
  column -t -s,

echo
echo "——— Total ———"

TOTAL_SQL="
WITH expanded AS (
    SELECT cost, (SELECT SUM(c.amount) FROM UNNEST(credits) c) AS credit_sum
    FROM \`$TABLE\`
    WHERE usage_start_time >= TIMESTAMP('$START')
    AND usage_end_time   <  TIMESTAMP('$END')
)
SELECT ROUND(SUM(cost + IFNULL(credit_sum, 0)), 2) AS total_cost
FROM expanded
"
bq --quiet query --nouse_legacy_sql --format=csv "$TOTAL_SQL" |
  awk -F, 'NR==1{print; next} {printf "%.2f\n", $1}'