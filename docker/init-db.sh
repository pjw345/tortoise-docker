#!/usr/bin/env bash
set -euo pipefail

MARKER_DIR="${INIT_MARKER_DIR:-/var/lib/turtle-init}"
MARKER_FILE="${MARKER_DIR}/initialized"
SQL_ROOT="${SQL_DIR:-/opt/turtle/sql}"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
DB_USER="${DB_USER:-mangos}"
DB_PASSWORD="${DB_PASSWORD:-mangos}"
DB_LOGIN="${DB_LOGIN:-tw_logon}"
DB_WORLD="${DB_WORLD:-tw_world}"
DB_CHAR="${DB_CHAR:-tw_char}"
DB_LOGS="${DB_LOGS:-tw_logs}"

REALM_NAME="${REALM_NAME:-TurtleWoW}"
REALM_ADDRESS="${REALM_ADDRESS:-127.0.0.1}"
WORLD_PORT="${WORLD_PORT:-8090}"
REALM_ID="${REALM_ID:-1}"

PLAYERBOTS_BUILT="${PLAYERBOTS_BUILT:-ON}"

if [[ -z "${DB_ROOT_PASSWORD}" ]]; then
  echo "DB_ROOT_PASSWORD (or MYSQL_ROOT_PASSWORD) is required." >&2
  exit 1
fi

mysql_root() {
  mysql -h"${DB_HOST}" -P"${DB_PORT}" -uroot -p"${DB_ROOT_PASSWORD}" --protocol=TCP "$@"
}

prepare_migrations_table() {
  local database="$1"

  mysql_root "${database}" <<'SQL'
CREATE TABLE IF NOT EXISTS `migrations` (
  `Id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `Name` VARCHAR(255) NOT NULL DEFAULT '0' COLLATE 'utf8_general_ci',
  `Module` VARCHAR(255) NOT NULL DEFAULT '' COLLATE 'utf8_general_ci',
  `Hash` VARCHAR(128) NOT NULL DEFAULT '0' COLLATE 'utf8_general_ci',
  `AppliedAt` DATETIME NOT NULL,
  PRIMARY KEY (`Id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8_general_ci;

ALTER TABLE `migrations`
  ADD COLUMN IF NOT EXISTS `Module`
  VARCHAR(255) NOT NULL DEFAULT '' COLLATE 'utf8_general_ci'
  AFTER `Name`;
SQL

  mysql_root "${database}" -e "DELETE FROM migrations WHERE Module = '';"
}

apply_migrations() {
  local database="$1"
  local label="$2"
  shift 2
  local files=("$@")

  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "No ${label} migration files found." >&2
    exit 1
  fi

  prepare_migrations_table "${database}"

  echo "Applying ${#files[@]} ${label} migrations..."

  for f in "${files[@]}"; do
    local name
    local hash
    local filtered_sql

    name="$(basename "${f}" .sql)"
    hash="$(sha1sum "${f}" | awk '{ print toupper($1) }')"
    filtered_sql="$(mktemp)"

    # The supplied base dumps already contain some rows introduced by older
    # migrations, but their migrations ledger is empty. INSERT IGNORE retains
    # existing base rows while still inserting missing rows from multi-row
    # migration statements. Any other SQL error remains fatal.
    sed -E \
      's/^([[:space:]]*)INSERT INTO/\1INSERT IGNORE INTO/' \
      "${f}" > "${filtered_sql}"

    echo "  -> ${name}"

    if ! mysql_root "${database}" < "${filtered_sql}"; then
      rm -f "${filtered_sql}"
      echo "Migration ${name} failed for ${database}." >&2
      exit 1
    fi

    rm -f "${filtered_sql}"

    mysql_root "${database}" -e "
      INSERT INTO migrations (Name, Module, Hash, AppliedAt)
      VALUES ('${name}', '', '${hash}', NOW());
    "
  done
}

echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 90); do
  if mysql_root -e "SELECT 1" &>/dev/null; then
    break
  fi

  if [[ "${i}" -eq 90 ]]; then
    echo "MariaDB did not become ready in time." >&2
    exit 1
  fi

  sleep 2
done
echo "MariaDB is ready."

if [[ -f "${MARKER_FILE}" ]]; then
  echo "Init marker found (${MARKER_FILE}); skipping database import."
  exit 0
fi

if [[ ! -f "${SQL_ROOT}/create_databases.sql" ]]; then
  echo "Missing ${SQL_ROOT}/create_databases.sql" >&2
  exit 1
fi

echo "Creating databases and base schemas..."
mysql_root < "${SQL_ROOT}/create_databases.sql"

character_inventory_copy_sql="${SQL_ROOT}/character-inventory-copy.sql"
if [[ ! -f "${character_inventory_copy_sql}" ]]; then
  echo "Missing ${character_inventory_copy_sql}" >&2
  exit 1
fi

echo "Ensuring character_inventory_copy exists..."
mysql_root "${DB_CHAR}" < "${character_inventory_copy_sql}"

echo "Creating application user '${DB_USER}' and grants..."
mysql_root <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_LOGIN}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_WORLD}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_CHAR}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_LOGS}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "Importing world content from sql/base (this can take several minutes)..."
shopt -s nullglob

base_files=("${SQL_ROOT}"/base/*.sql)
if [[ "${#base_files[@]}" -eq 0 ]]; then
  echo "No SQL files found under ${SQL_ROOT}/base" >&2
  exit 1
fi

for f in "${base_files[@]}"; do
  echo "  -> $(basename "${f}")"
  mysql_root "${DB_WORLD}" < "${f}"
done

normalized="$(echo "${PLAYERBOTS_BUILT}" | tr '[:lower:]' '[:upper:]')"
if [[ "${normalized}" == "ON" || "${normalized}" == "1" || "${normalized}" == "TRUE" ]]; then
  PB_SQL="${SQL_ROOT}/playerbots"

  if [[ ! -d "${PB_SQL}" ]]; then
    echo "PLAYERBOTS_BUILT=${PLAYERBOTS_BUILT} but ${PB_SQL} is missing." >&2
    exit 1
  fi

  echo "Importing playerbots world SQL..."
  cat "${PB_SQL}"/world/*.sql \
      "${PB_SQL}"/world/classic/*.sql |
    mysql_root "${DB_WORLD}"

  echo "Importing playerbots characters SQL..."
  cat "${PB_SQL}"/characters/*.sql |
    mysql_root "${DB_CHAR}"
else
  echo "Skipping playerbots SQL (PLAYERBOTS_BUILT=${PLAYERBOTS_BUILT})."
fi

character_update_files=(
  "${SQL_ROOT}"/database_updates/character/*.sql
)
world_update_files=(
  "${SQL_ROOT}"/database_updates/world/*.sql
)

apply_migrations \
  "${DB_CHAR}" \
  "character" \
  "${character_update_files[@]}"

apply_migrations \
  "${DB_WORLD}" \
  "world" \
  "${world_update_files[@]}"

script_name_count="$(
  mysql_root -N "${DB_WORLD}" -e "
    SELECT COUNT(*)
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = '${DB_WORLD}'
      AND TABLE_NAME = 'spell_template'
      AND COLUMN_NAME = 'script_name';
  "
)"

if [[ "${script_name_count}" != "1" ]]; then
  echo "spell_template.script_name is missing after migrations." >&2
  exit 1
fi

unique_index_count="$(
  mysql_root -N "${DB_CHAR}" -e "
    SELECT COUNT(*)
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = '${DB_CHAR}'
      AND TABLE_NAME = 'ai_playerbot_random_bots'
      AND INDEX_NAME = 'uq_owner_bot_event'
      AND NON_UNIQUE = 0;
  "
)"

if [[ "${unique_index_count}" != "3" ]]; then
  echo "uq_owner_bot_event was not created correctly." >&2
  exit 1
fi

echo "Inserting realmlist row..."
mysql_root <<SQL
DELETE FROM ${DB_LOGIN}.realmlist;
INSERT INTO ${DB_LOGIN}.realmlist
  (id, name, address, port, icon, realmflags, timezone, allowedSecurityLevel, realmbuilds)
VALUES
  (${REALM_ID}, '${REALM_NAME}', '${REALM_ADDRESS}', ${WORLD_PORT}, 0, 0, 1, 0, '7272');
SQL

mkdir -p "${MARKER_DIR}"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER_FILE}"
echo "Database init complete."
