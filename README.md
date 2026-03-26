# NetBird Monitor

Мониторинг пиров NetBird с уведомлениями в Gotify и логированием в SQLite.

## Возможности

- ✅ Проверка статуса пиров через `netbird status --json`
- ✅ Уведомления в Gotify только при изменении статуса (подключение/отключение)
- ✅ Автоматическое определение новых пиров
- ✅ Логирование всех событий в SQLite базу данных
- ✅ Сохранение предыдущего состояния для детектирования изменений
- ✅ Запуск как systemd-сервис (автоматический рестарт при сбоях)
- ✅ Конфигурация через `.env` файл

## Структура

```
netbird-monitor/
├── .env                 # Конфигурация ( secrets )
├── .env.example         # Шаблон конфигурации
├── .gitignore           # Исключения для git
├── config.sh            # Загрузка конфигурации
├── monitor.sh           # Основной скрипт мониторинга
├── init_db.sh           # Скрипт инициализации БД
├── install.sh           # Скрипт установки
├── netbird-monitor.service  # systemd-сервис
├── data/
│   ├── status.db        # SQLite база данных
│   └── monitor.log      # Лог файл
└── README.md
```

## Установка

### 1. Клонирование репозитория

```bash
git clone https://github.com/yanik-v86/netbird-monitor.git
cd netbird-monitor
```

### 2. Настройка конфигурации

```bash
cp .env.example .env
nano .env
```

Отредактируйте `.env`:
- `GOTIFY_URL` — URL вашего Gotify сервера
- `GOTIFY_TOKEN` — токен приложения Gotify
- `NETBIRD_DOMAIN` — домен для извлечения имени хоста (например, `dobryinik.cloud`)

### 3. Запуск установки

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

### Ручной запуск (альтернатива)

```bash
chmod +x monitor.sh
./monitor.sh
```

## Использование

### Systemd сервис

```bash
# Старт
sudo systemctl start netbird-monitor

# Статус
sudo systemctl status netbird-monitor

# Логи
sudo journalctl -u netbird-monitor -f

# Перезапуск
sudo systemctl restart netbird-monitor
```

### Настройка интервала проверки

В файле `.env` измените `CHECK_INTERVAL` (по умолчанию 30 секунд):

```bash
CHECK_INTERVAL=60
```

## База данных

### Таблица `events`

| Поле | Тип | Описание |
|------|-----|----------|
| id | INTEGER | Первичный ключ |
| peer_id | TEXT | Public key пира |
| peer_name | TEXT | FQDN пира |
| status | TEXT | Статус: `up`, `down` или `disconnected` |
| timestamp | TEXT | Время события |

### Таблица `current_states`

| Поле | Тип | Описание |
|------|-----|----------|
| peer_id | TEXT | Public key пира (PK) |
| peer_name | TEXT | FQDN пира |
| status | TEXT | Текущий статус |
| raw_status | TEXT | Статус от NetBird |
| prev_status | TEXT | Предыдущий статус |
| updated_at | TEXT | Время обновления |

### Примеры запросов

```bash
# Последние 10 событий
sqlite3 data/status.db "SELECT * FROM events ORDER BY timestamp DESC LIMIT 10;"

# Все отключения за сегодня
sqlite3 data/status.db "SELECT * FROM events WHERE status='down' AND date(timestamp)=date('now');"

# Текущие состояния пиров
sqlite3 data/status.db "SELECT peer_name, status, prev_status FROM current_states;"
```

## Уведомления Gotify

Уведомления отправляются только при изменении статуса:

| Событие | Заголовок | Приоритет |
|---------|-----------|-----------|
| Пир подключился | Netbird: {hostname} 🟢 | 3 |
| Пир отключился | Netbird: {hostname} 🔴 | 5 |
| Пир недоступен | Netbird: {hostname} 🔴 | 5 |
| Новый пир | Netbird: Новый пир 🆕 | 4 |

## Требования

- `netbird` CLI (установлен и настроен)
- `jq` для парсинга JSON
- `sqlite3` для работы с БД
- `curl` для отправки уведомлений
- `bash` >= 4.0

## Лицензия

MIT
