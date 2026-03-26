#!/bin/bash
# Скрипт установки и настройки netbird-monitor

set -euo pipefail

# Определяем директорию скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Проверка зависимостей
check_dependencies() {
    log_info "Проверка зависимостей..."
    
    local missing=()
    
    if ! command -v netbird &> /dev/null; then
        missing+=("netbird")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v sqlite3 &> /dev/null; then
        missing+=("sqlite3")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Отсутствуют зависимости: ${missing[*]}"
        log_info "Установите их командой:"
        
        if command -v apt &> /dev/null; then
            echo "  sudo apt install ${missing[*]}"
        elif command -v pacman &> /dev/null; then
            echo "  sudo pacman -S ${missing[*]}"
        elif command -v dnf &> /dev/null; then
            echo "  sudo dnf install ${missing[*]}"
        else
            echo "  Используйте ваш пакетный менеджер"
        fi
        
        exit 1
    fi
    
    log_info "Все зависимости установлены"
}

# Создание директорий
create_directories() {
    log_info "Создание директорий..."
    
    mkdir -p "${SCRIPT_DIR}/data"
    mkdir -p "${SCRIPT_DIR}/logs"
    
    log_info "Директории созданы"
}

# Инициализация базы данных
init_database() {
    log_info "Инициализация базы данных..."
    
    local db_path="${SCRIPT_DIR}/data/status.db"
    
    sqlite3 "${db_path}" <<EOF
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id TEXT NOT NULL,
    peer_name TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_peer_id ON events(peer_id);
CREATE INDEX IF NOT EXISTS idx_timestamp ON events(timestamp);
EOF
    
    log_info "База данных инициализирована: ${db_path}"
}

# Проверка прав доступа к скриптам
set_permissions() {
    log_info "Установка прав доступа..."
    
    chmod +x "${SCRIPT_DIR}/monitor.sh"
    chmod +x "${SCRIPT_DIR}/init_db.sh"
    chmod +x "${SCRIPT_DIR}/install.sh"
    
    log_info "Права доступа установлены"
}

# Проверка конфигурации
check_config() {
    log_info "Проверка конфигурации..."
    
    if [[ ! -f "${SCRIPT_DIR}/config.sh" ]]; then
        log_error "Файл config.sh не найден!"
        exit 1
    fi
    
    # Проверяем, что токены не пустые (базовая проверка)
    source "${SCRIPT_DIR}/config.sh"
    
    if [[ -z "${GOTIFY_URL:-}" ]]; then
        log_warn "GOTIFY_URL не настроен в config.sh"
    fi
    
    if [[ -z "${GOTIFY_TOKEN:-}" ]]; then
        log_warn "GOTIFY_TOKEN не настроен в config.sh"
    fi
    
    log_info "Конфигурация проверена"
}

# Установка systemd-сервиса
install_systemd_service() {
    log_info "Настройка systemd-сервиса..."
    
    if [[ $EUID -ne 0 ]]; then
        log_warn "Запустите скрипт от root для установки systemd-сервиса"
        log_info "Или выполните вручную после установки:"
        echo ""
        echo "  sudo cp ${SCRIPT_DIR}/netbird-monitor.service /etc/systemd/system/"
        echo "  sudo systemctl daemon-reload"
        echo "  sudo systemctl enable --now netbird-monitor"
        echo ""
        return
    fi
    
    # Копируем сервис
    cp "${SCRIPT_DIR}/netbird-monitor.service" /etc/systemd/system/
    
    # Перезагружаем systemd
    systemctl daemon-reload
    
    # Включаем и запускаем сервис
    systemctl enable netbird-monitor
    systemctl start netbird-monitor
    
    log_info "Systemd-сервис установлен и запущен"
    
    # Показываем статус
    echo ""
    systemctl status netbird-monitor --no-pager || true
}

# Тестовый запуск
test_run() {
    log_info "Тестовый запуск мониторинга..."
    
    # Проверяем, что netbird работает
    if ! netbird status > /dev/null 2>&1; then
        log_warn "Netbird не отвечает. Убедитесь, что служба запущена."
    else
        log_info "Netbird работает корректно"
    fi
    
    # Показываем текущих пиров
    echo ""
    log_info "Текущие пиры:"
    netbird status --json 2>/dev/null | jq -r '.peers.details[]? | "  \(.fqdn): \(.status)"' || true
    echo ""
}

# Вывод итоговой информации
show_summary() {
    echo ""
    echo "========================================"
    log_info "Установка завершена!"
    echo "========================================"
    echo ""
    echo "Структура проекта:"
    echo "  ${SCRIPT_DIR}/"
    echo "  ├── config.sh              # Конфигурация"
    echo "  ├── monitor.sh             # Скрипт мониторинга"
    echo "  ├── init_db.sh             # Инициализация БД"
    echo "  ├── install.sh             # Скрипт установки"
    echo "  ├── netbird-monitor.service # systemd-сервис"
    echo "  └── data/"
    echo "      ├── status.db          # База данных"
    echo "      └── previous_state.json # Кэш состояния"
    echo ""
    echo "Для запуска вручную:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  ./monitor.sh"
    echo ""
    echo "Для просмотра логов (systemd):"
    echo "  journalctl -u netbird-monitor -f"
    echo ""
    echo "Для просмотра событий в БД:"
    echo "  sqlite3 ${SCRIPT_DIR}/data/status.db \"SELECT * FROM events ORDER BY timestamp DESC LIMIT 10;\""
    echo ""
}

# Основная функция
main() {
    echo ""
    echo "========================================"
    echo "  NetBird Monitor - Установка"
    echo "========================================"
    echo ""
    
    check_dependencies
    create_directories
    init_database
    set_permissions
    check_config
    test_run
    
    # Спрашиваем про установку systemd
    echo ""
    read -p "Установить systemd-сервис? (требуются права root) [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_systemd_service
    else
        log_info "Systemd-сервис не установлен"
        log_info "Для установки вручную выполните:"
        echo ""
        echo "  sudo cp ${SCRIPT_DIR}/netbird-monitor.service /etc/systemd/system/"
        echo "  sudo systemctl daemon-reload"
        echo "  sudo systemctl enable --now netbird-monitor"
        echo ""
    fi
    
    show_summary
}

main "$@"
