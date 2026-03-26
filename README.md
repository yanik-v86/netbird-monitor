# NetBird Monitor

Мониторинг пиров NetBird с уведомлениями в Gotify и логированием в SQLite.

## Возможности

- ✅ Проверка статуса пиров через `netbird status --json`
- ✅ Уведомления в Gotify при изменении статуса (подключение/отключение)
- ✅ Логирование всех событий в SQLite базу данных
- ✅ Сохранение предыдущего состояния для детектирования изменений
- ✅ Запуск как systemd-сервис (автоматический рестарт при сбоях)

## Структура

```
netbird-monitor/
├── config.sh           # Конфигурация (URL Gotify, токены, интервалы)
├── monitor.sh          # Основной скрипт мониторинга
├── init_db.sh          # Скрипт инициализации БД
├── netbird-monitor.service  # systemd-сервис
├── data/
│   ├── status.db       # SQLite база данных событий
│   ├── previous_state.json  # Кэш предыдущего состояния
│   └── monitor.log     # Лог файл
└── README.md
```

## Установка

### Автоматическая установка (рекомендуется)

```bash
chmod +x install.sh
./install.sh
```

Скрипт автоматически:
- Проверит зависимости (`netbird`, `jq`, `sqlite3`, `curl`)
- Создаст необходимые директории
- Инициализирует базу данных
- Настроит права доступа
- Предложит установить systemd-сервис

### Ручная установка

#### 1. Проверка зависимостей

```bash
# Проверка netbird
netbird version

# Проверка jq (необходим для парсинга JSON)
jq --version

# Если jq не установлен:
# Ubuntu/Debian
sudo apt install jq

# Arch Linux
sudo pacman -S jq
```

#### 2. Настройка конфигурации

Отредактируйте `config.sh`:

```bash
nano config.sh
```

Измените параметры:
- `GOTIFY_URL` — URL вашего Gotify сервера
- `GOTIFY_TOKEN` — токен приложения Gotify
- `CHECK_INTERVAL` — интервал проверки в секундах (по умолчанию 30)

#### 3. Инициализация базы данных

```bash
chmod +x init_db.sh
./init_db.sh
```

#### 4. Запуск

```bash
# Сделать скрипт исполняемым
chmod +x monitor.sh

# Скопировать сервис в systemd (путь может отличаться)
# Отредактируйте файл netbird-monitor.service, заменив %h на ваш домашний каталог
# или используйте абсолютные пути

# Для установки (замените username на ваше имя пользователя):
sudo cp netbird-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable netbird-monitor
sudo systemctl start netbird-monitor

# Проверка статуса
systemctl status netbird-monitor

# Просмотр логов
journalctl -u netbird-monitor -f
```

#### Вариант B: Ручной запуск

```bash
chmod +x monitor.sh
./monitor.sh
```

#### Вариант C: В фоне (nohup)

```bash
nohup ./monitor.sh > /dev/null 2>&1 &
```

## База данных

### Таблица `events`

| Поле | Тип | Описание |
|------|-----|----------|
| id | INTEGER | Первичный ключ |
| peer_id | TEXT | Public key пира |
| peer_name | TEXT | FQDN пира (например, server.dobryinik.cloud) |
| status | TEXT | Статус: `up` или `down` |
| timestamp | TEXT | Время события (YYYY-MM-DD HH:MM:SS) |

### Примеры запросов

```bash
# Последние 10 событий
sqlite3 data/status.db "SELECT * FROM events ORDER BY timestamp DESC LIMIT 10;"

# Все отключения за сегодня
sqlite3 data/status.db "SELECT * FROM events WHERE status='down' AND date(timestamp)=date('now');"

# Статистика по пирам
sqlite3 data/status.db "SELECT peer_name, COUNT(*) as events, SUM(CASE WHEN status='up' THEN 1 ELSE 0 END) as ups, SUM(CASE WHEN status='down' THEN 1 ELSE 0 END) as downs FROM events GROUP BY peer_name;"
```

## Логи

- **Лог мониторинга:** `data/monitor.log`
- **Системные логи (systemd):** `journalctl -u netbird-monitor -f`

## Уведомления Gotify

При изменении статуса пира отправляются уведомления:

- **Подключение (up):** приоритет 3 (обычный)
- **Отключение (down):** приоритет 5 (высокий)

## Требования

- `netbird` CLI (установлен и настроен)
- `jq` для парсинга JSON
- `sqlite3` для работы с БД
- `curl` для отправки уведомлений
- `bash` >= 4.0

## Лицензия

MIT
