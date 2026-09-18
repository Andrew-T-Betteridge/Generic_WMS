#!/usr/bin/env bash
set -euo pipefail

TARGET=""
DATABASE=""
HOSTNAME_DB="127.0.0.1"
PORT="5432"
DBUSER="dynetic_app"
CONFIRM_PROD="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --database) DATABASE="${2:-}"; shift 2 ;;
    --host) HOSTNAME_DB="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --user) DBUSER="${2:-}"; shift 2 ;;
    --confirm-production-release) CONFIRM_PROD="yes"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

stop() {
  echo
  echo "BOOTSTRAP BLOCKED: $*" >&2
  exit 1
}

[[ "$TARGET" == "VERIFY" || "$TARGET" == "PROD" ]] || stop "--target must be VERIFY or PROD"
[[ -n "$DATABASE" ]] || stop "--database is required"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/database/bootstrap/fresh-install-manifest.txt"

[[ -f "$MANIFEST" ]] || stop "Fresh-install manifest is missing."

if [[ "$TARGET" == "VERIFY" ]]; then
  [[ "$DATABASE" == "fulfilment_bootstrap_verify" ]] || stop "VERIFY may only target fulfilment_bootstrap_verify."
fi

if [[ "$TARGET" == "PROD" ]]; then
  [[ "$DATABASE" == "fulfilment_prod" ]] || stop "PROD may only target fulfilment_prod."
  [[ "$CONFIRM_PROD" == "yes" ]] || stop "PROD requires --confirm-production-release."

  [[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ]] ||
    stop "Tracked working-tree changes exist."

  TAG="$(git -C "$REPO_ROOT" tag --points-at HEAD 'dynetic-wms-v0.3.6' || true)"
  [[ "$TAG" == "dynetic-wms-v0.3.6" ]] ||
    stop "PROD requires HEAD tagged exactly dynetic-wms-v0.3.6."
fi

mapfile -t ENTRIES < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")
[[ "${#ENTRIES[@]}" -gt 0 ]] || stop "Fresh-install manifest is empty."

for entry in "${ENTRIES[@]}"; do
  if [[ "$entry" =~ (^|/)tests?(/|$)|(^|/)fixtures?(/|$)|(^|/)samples?(/|$)|(^|/)demo(/|$)|(^|/)load[-_]?tests?(/|$)|smoke.*\.sql$|fixture.*\.sql$|load.*\.sql$ ]]; then
    stop "Forbidden test/fixture/demo/load path in manifest: $entry"
  fi
  [[ "$entry" == *.sql ]] || stop "Only .sql files are permitted: $entry"
  [[ -f "$REPO_ROOT/$entry" ]] || stop "Manifest file does not exist: $entry"

  if [[ "$TARGET" == "PROD" ]]; then
    git -C "$REPO_ROOT" ls-files --error-unmatch -- "$entry" >/dev/null 2>&1 ||
      stop "Manifest SQL is not committed in the release: $entry"
  fi
done

read -r -s -p "Database password for $DBUSER: " PGPASSWORD
echo
export PGPASSWORD
trap 'unset PGPASSWORD' EXIT

ACTUAL_DB="$(psql -X -v ON_ERROR_STOP=1 -h "$HOSTNAME_DB" -p "$PORT" -U "$DBUSER" -d "$DATABASE" -Atc 'select current_database();')"
[[ "$ACTUAL_DB" == "$DATABASE" ]] || stop "Connected database '$ACTUAL_DB' does not match '$DATABASE'."

OBJECT_COUNT="$(psql -X -v ON_ERROR_STOP=1 -h "$HOSTNAME_DB" -p "$PORT" -U "$DBUSER" -d "$DATABASE" -Atc "
SELECT
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema NOT IN ('pg_catalog','information_schema')) +
  (SELECT count(*) FROM information_schema.schemata
    WHERE schema_name IN ('api','audit','config','core','interface'));
")"

[[ "$OBJECT_COUNT" == "0" ]] || stop "Database is not empty. Fresh bootstrap is forbidden."

echo
echo "DYNETIC FRESH DATABASE BOOTSTRAP"
echo "Target   : $TARGET"
echo "Database : $DATABASE"
echo "Files    : ${#ENTRIES[@]}"
echo

for entry in "${ENTRIES[@]}"; do
  echo "Applying: $entry"
  psql -X -v ON_ERROR_STOP=1 -h "$HOSTNAME_DB" -p "$PORT" -U "$DBUSER" -d "$DATABASE" -f "$REPO_ROOT/$entry"
done

echo
echo "BOOTSTRAP COMPLETE"
