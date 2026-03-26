#!/bin/bash
# Скрипт инициализации базы данных с поддержкой хранения текущего состояния пиров

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Создаём директорию для данных
mkdir -p "$(dirname "${DB_PATH}")"

# Инициализируем БД
sqlite3 "${DB_PATH}" <<EOF
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id TEXT NOT NULL,
    peer_name TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS current_states (
    peer_id TEXT PRIMARY KEY,
    peer_name TEXT NOT NULL,
    status TEXT NOT NULL,
    raw_status TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_peer_id ON events(peer_id);
CREATE INDEX IF NOT EXISTS idx_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_current_states_peer_id ON current_states(peer_id);
EOF

echo "База данных инициализирована: ${DB_PATH}"

# Если существует старый файл состояния, переносим его в базу данных
if [[ -f "${STATE_FILE}" ]]; then
    echo "Перенос данных из ${STATE_FILE} в базу данных..."
    
    # Читаем JSON и вставляем в таблицу current_states
    jq -c '.[]' "${STATE_FILE}" | while read -r item; do
        peer_id=$(echo "${item}" | jq -r '.public_key')
        peer_name=$(echo "${item}" | jq -r '.fqdn')
        status=$(echo "${item}" | jq -r '.status')
        raw_status=$(echo "${item}" | jq -r '.raw_status')
        updated_at=$(date '+%Y-%m-%d %H:%M:%S')
        
        sqlite3 "${DB_PATH}" \
            "INSERT OR REPLACE INTO current_states (peer_id, peer_name, status, raw_status, updated_at) VALUES ('${peer_id}', '${peer_name}', '${status}', '${raw_status}', '${updated_at}');"
    done
    
    echo "Данные перенесены в базу данных."
fi