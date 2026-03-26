#!/bin/bash
# Скрипт мониторинга пиров NetBird с уведомлениями в Gotify и логированием в SQLite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Логирование
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "${LOG_FILE}"
}

# Извлечение имени хоста без домена
get_hostname() {
    local fqdn="$1"
    if [[ -n "${NETBIRD_DOMAIN:-}" ]]; then
        echo "${fqdn%%.${NETBIRD_DOMAIN}}"
    else
        echo "${fqdn}"
    fi
}

# Отправка уведомления в Gotify
send_gotify_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-3}"
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "${GOTIFY_URL}/message" \
        -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"title\":\"${title}\",\"message\":\"${message}\",\"priority\":${priority}}")
    
    local http_code
    http_code=$(echo "${response}" | tail -n1)
    
    if [[ ${http_code} -eq 200 ]]; then
        log "Уведомление отправлено в Gotify: ${title}"
    else
        log "Ошибка отправки уведомления в Gotify: HTTP ${http_code}, заголовок: ${title}"
        log "Ответ сервера: $(echo "${response}" | head -n -1)"
    fi
}

# Запись события в SQLite
log_event_to_db() {
    local peer_id="$1"
    local peer_name="$2"
    local status="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    sqlite3 "${DB_PATH}" \
        "INSERT INTO events (peer_id, peer_name, status, timestamp) VALUES ('${peer_id}', '${peer_name}', '${status}', '${timestamp}');"
    
    log "Событие записано в БД: ${peer_name} -> ${status}"
}

# Получение статуса пиров от NetBird
get_peers_status() {
    netbird status --json 2>/dev/null | jq -c '
        .peers.details[]? | 
        {
            fqdn: .fqdn,
            public_key: .publicKey,
            status: (if .status == "Connected" then "up" else "down" end),
            raw_status: .status
        }
    '
}

# Основная логика проверки
check_peers() {
    local current_state
    local previous_state
    
    # Получаем текущее состояние
    current_state=$(get_peers_status | jq -s 'sort_by(.public_key)')
    
    # Получаем предыдущее состояние из базы данных
    local db_previous_state
    db_previous_state=$(sqlite3 "${DB_PATH}" "SELECT peer_id, peer_name, status, raw_status, COALESCE(prev_status, '') as prev_status FROM current_states;" 2>/dev/null || echo "")
    
    if [[ -n "${db_previous_state}" ]]; then
        # Преобразуем данные из базы в JSON формат
        previous_state=$(echo "${db_previous_state}" | awk -F'|' 'BEGIN {print "["} {if(NR>1) printf(","); printf("{\"public_key\":\"%s\",\"fqdn\":\"%s\",\"status\":\"%s\",\"raw_status\":\"%s\",\"prev_status\":\"%s\"}", $1, $2, $3, $4, $6)} END {print "]"}')
        
        # Находим изменения и новых пиров
        local changes
        changes=$(jq -n --argjson current "${current_state}" --argjson previous "${previous_state}" '
            ($current | map({(.public_key): .}) | add) as $current_map |
            ($previous | map({(.public_key): .}) | add) as $previous_map |

            [
                ($current[] | select(
                    .public_key as $key |
                    $previous_map[$key].status != .status
                ) | . + {prev_status: $previous_map[.public_key].status}),
                ($previous[] | select(
                    .public_key as $key |
                    $current_map[$key] == null
                ) | . + {status: "disconnected", prev_status: .status})
            ]
        ')

        # Находим новых пиров (которые есть в current, но нет в previous)
        local new_peers
        new_peers=$(jq -n --argjson current "${current_state}" --argjson previous "${previous_state}" '
            ($previous | map(.public_key)) as $previous_keys |
            [$current[] | select((.public_key as $key | $previous_keys | index($key)) == null)]
        ')

        # Обрабатываем изменения
        while IFS= read -r change; do
            peer_name=$(echo "${change}" | jq -r '.fqdn')
            peer_id=$(echo "${change}" | jq -r '.public_key')
            new_status=$(echo "${change}" | jq -r '.status')
            previous_status=$(echo "${change}" | jq -r '.prev_status // empty')
            
            notify_if_changed "${peer_id}" "${peer_name}" "${new_status}" "${previous_status}"
        done < <(echo "${changes}" | jq -c '.[]' 2>/dev/null)

        # Обрабатываем новых пиров
        if [[ $(echo "${new_peers}" | jq 'length') -gt 0 ]]; then
            while IFS= read -r new_peer; do
                peer_name=$(echo "${new_peer}" | jq -r '.fqdn')
                peer_id=$(echo "${new_peer}" | jq -r '.public_key')
                peer_status=$(echo "${new_peer}" | jq -r '.status')
                hostname=$(get_hostname "${peer_name}")

                log "Обнаружен новый пир: ${peer_name}"

                # Уведомление о новом пире
                if [[ "${peer_status}" == "up" ]]; then
                    send_gotify_notification \
                        "Netbird: Новый пир 🆕" \
                        "${peer_name} (${hostname}) подключился к сети" \
                        "4"
                    log_event_to_db "${peer_id}" "${peer_name}" "new_up"
                else
                    send_gotify_notification \
                        "Netbird: Новый пир 🆕" \
                        "${peer_name} (${hostname}) добавлен в сеть (статус: ${peer_status})" \
                        "3"
                    log_event_to_db "${peer_id}" "${peer_name}" "new_down"
                fi
            done < <(echo "${new_peers}" | jq -c '.[]' 2>/dev/null)
        fi
    else
        log "Предыдущее состояние не найдено в базе данных. Инициализация..."
        # При первом запуске просто сохраняем текущее состояние без уведомлений о новых пирах
        update_current_states_from_json "${current_state}"
        return
    fi
    
    # Обновляем текущие состояния в базе данных
    update_current_states_from_json "${current_state}"
}

# Функция для обновления текущих состояний из JSON
update_current_states_from_json() {
    local json_data="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Парсим JSON и обновляем записи в базе данных
    while IFS= read -r item; do
        peer_id=$(echo "${item}" | jq -r '.public_key')
        peer_name=$(echo "${item}" | jq -r '.fqdn')
        status=$(echo "${item}" | jq -r '.status')
        raw_status=$(echo "${item}" | jq -r '.raw_status')
        
        local prev_status
        prev_status=$(sqlite3 "${DB_PATH}" "SELECT status FROM current_states WHERE peer_id='${peer_id}';" 2>/dev/null || echo "")
        
        sqlite3 "${DB_PATH}" \
            "INSERT OR REPLACE INTO current_states (peer_id, peer_name, status, raw_status, prev_status, updated_at) VALUES ('${peer_id}', '${peer_name}', '${status}', '${raw_status}', '${prev_status}', '${timestamp}');"
    done < <(echo "${json_data}" | jq -c '.[]')
}

# Проверка и отправка уведомления только при изменении статуса
notify_if_changed() {
    local peer_id="$1"
    local peer_name="$2"
    local new_status="$3"
    local previous_status="$4"
    
    if [[ "${new_status}" != "${previous_status}" ]]; then
        local hostname
        hostname=$(get_hostname "${peer_name}")
        
        case "${new_status}" in
            up)
                send_gotify_notification \
                    "Netbird: ${hostname} 🟢" \
                    "Пир ${peer_name} теперь доступен" \
                    "3"
                log_event_to_db "${peer_id}" "${peer_name}" "up"
                ;;
            down)
                send_gotify_notification \
                    "Netbird: ${hostname} 🔴" \
                    "Пир ${peer_name} недоступен" \
                    "5"
                log_event_to_db "${peer_id}" "${peer_name}" "down"
                ;;
            disconnected)
                send_gotify_notification \
                    "Netbird: ${hostname} 🔴" \
                    "Пир ${peer_name} отключился от сети" \
                    "5"
                log_event_to_db "${peer_id}" "${peer_name}" "disconnected"
                ;;
        esac
    fi
}

# Инициализация
init() {
    # Создаём директорию для данных
    mkdir -p "$(dirname "${DB_PATH}")"
    #mkdir -p "$(dirname "${STATE_FILE}")"
    mkdir -p "$(dirname "${LOG_FILE}")"
    
    # Инициализируем БД если не существует
    if [[ ! -f "${DB_PATH}" ]]; then
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
    prev_status TEXT,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_peer_id ON events(peer_id);
CREATE INDEX IF NOT EXISTS idx_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_current_states_peer_id ON current_states(peer_id);
EOF
        log "База данных инициализирована: ${DB_PATH}"
    fi
    
    log "Мониторинг запущен. Интервал: ${CHECK_INTERVAL} сек"
}

# Основной цикл
main() {
    init
    
    while true; do
        check_peers
        sleep "${CHECK_INTERVAL}"
    done
}

main "$@"
