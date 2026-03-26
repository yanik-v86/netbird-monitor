#!/bin/bash
# Конфигурация netbird-monitor

# Пути
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загрузка переменных из .env
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Интервал проверки (секунды)
CHECK_INTERVAL=30

# Пути к файлам
DB_PATH="${SCRIPT_DIR}/data/status.db"
LOG_FILE="${SCRIPT_DIR}/data/monitor.log"

# Экспорт переменных
export GOTIFY_URL GOTIFY_TOKEN CHECK_INTERVAL DB_PATH LOG_FILE SCRIPT_DIR NETBIRD_DOMAIN
