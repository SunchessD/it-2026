-- ============================================================
-- Веб-сервис онлайн-записи «Окошко»
-- Создание структуры базы данных (SQLite / DBeaver)
-- ============================================================

PRAGMA foreign_keys = ON;

-- ============================================================
-- МОДУЛЬ «УЧЁТНЫЕ ЗАПИСИ И ДОСТУП»
-- ============================================================

-- УчётнаяЗапись: пользователи сервиса (клиенты, мастера, администраторы)
CREATE TABLE web_accounts (
    account_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name                VARCHAR(64) NOT NULL,
    email               VARCHAR(254) NOT NULL UNIQUE,
    password_hash       VARCHAR(255) NOT NULL,
    role                VARCHAR(20) NOT NULL DEFAULT 'user'
                        CHECK (role IN ('user', 'admin')),
    status              VARCHAR(20) NOT NULL DEFAULT 'inactive'
                        CHECK (status IN ('inactive', 'active', 'blocked')),
    privacy_accepted_at TIMESTAMP,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at       TIMESTAMP
);

-- Токен: одноразовые токены активации, сброса пароля, привязки и входа через Telegram
CREATE TABLE tokens (
    token_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id  INTEGER NOT NULL REFERENCES web_accounts(account_id) ON DELETE CASCADE,
    purpose     VARCHAR(20) NOT NULL
                CHECK (purpose IN ('activate', 'reset', 'tg_link', 'tg_login')),
    token_hash  VARCHAR(64) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  TIMESTAMP NOT NULL,
    used_at     TIMESTAMP
);

CREATE INDEX idx_tokens_account_purpose ON tokens(account_id, purpose, created_at);

-- Сессия: активные веб-сессии пользователей (срок действия 30 дней)
CREATE TABLE web_sessions (
    session_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id   INTEGER NOT NULL REFERENCES web_accounts(account_id) ON DELETE CASCADE,
    token_hash   VARCHAR(64) NOT NULL UNIQUE,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   TIMESTAMP NOT NULL,
    last_seen_at TIMESTAMP,
    revoked_at   TIMESTAMP
);

CREATE INDEX idx_web_sessions_account ON web_sessions(account_id);

-- ПривязкаTelegram: связь учётной записи на сайте с Telegram ID (1 : 0..1)
CREATE TABLE telegram_links (
    link_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id  INTEGER NOT NULL UNIQUE REFERENCES web_accounts(account_id) ON DELETE CASCADE,
    tg_user_id  BIGINT NOT NULL UNIQUE,
    tg_name     VARCHAR(128),
    tg_username VARCHAR(64),
    linked_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- МОДУЛЬ «МАСТЕРА, КАНАЛЫ И УСЛУГИ»
-- ============================================================

-- Мастер: профиль и настройки рабочего пространства мастера
CREATE TABLE masters (
    master_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_account_id INTEGER NOT NULL REFERENCES web_accounts(account_id) ON DELETE CASCADE,
    public_id        VARCHAR(16) NOT NULL UNIQUE,
    master_name      VARCHAR(128) NOT NULL,
    specialty        VARCHAR(128),
    address_text     TEXT,
    address_mode     VARCHAR(16) NOT NULL DEFAULT 'place'
                     CHECK (address_mode IN ('place', 'online', 'visit')),
    timezone         VARCHAR(64) NOT NULL DEFAULT 'Europe/Moscow',
    manual_confirm   BOOLEAN NOT NULL DEFAULT 0,
    status           VARCHAR(24) NOT NULL DEFAULT 'active'
                     CHECK (status IN ('setup', 'active', 'paused', 'disabled')),
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_masters_owner ON masters(owner_account_id);

-- ЛичныйСайтМастера: публичная веб-страница okoshko.site/<slug> (1 : 0..1)
CREATE TABLE master_sites (
    site_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id    INTEGER NOT NULL UNIQUE REFERENCES masters(master_id) ON DELETE CASCADE,
    slug         VARCHAR(48) NOT NULL UNIQUE,
    palette      VARCHAR(24) NOT NULL DEFAULT 'ocean',
    headline     VARCHAR(160),
    about_text   TEXT,
    is_published BOOLEAN NOT NULL DEFAULT 1,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- БотМастера: подключённый Telegram-бот мастера (1 : 0..1)
CREATE TABLE master_bots (
    bot_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id    INTEGER NOT NULL UNIQUE REFERENCES masters(master_id) ON DELETE CASCADE,
    tg_bot_id    BIGINT NOT NULL UNIQUE,
    bot_username VARCHAR(64) NOT NULL UNIQUE,
    token_enc    TEXT NOT NULL,
    status       VARCHAR(24) NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'paused', 'revoked')),
    connected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Услуга: позиции прайс-листа мастера
CREATE TABLE services (
    service_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id        INTEGER NOT NULL REFERENCES masters(master_id) ON DELETE CASCADE,
    title            VARCHAR(128) NOT NULL,
    category         VARCHAR(64),
    duration_min     INTEGER NOT NULL DEFAULT 60
                     CHECK (duration_min BETWEEN 5 AND 720),
    buffer_after_min INTEGER NOT NULL DEFAULT 0
                     CHECK (buffer_after_min BETWEEN 0 AND 240),
    price_from       INTEGER CHECK (price_from IS NULL OR price_from >= 0),
    price_to         INTEGER CHECK (price_to IS NULL OR price_to >= 0),
    price_type       VARCHAR(16) NOT NULL DEFAULT 'exact'
                     CHECK (price_type IN ('exact', 'from', 'range', 'hourly')),
    is_active        BOOLEAN NOT NULL DEFAULT 1,
    sort_order       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_services_master_active ON services(master_id, is_active, sort_order);

-- ============================================================
-- МОДУЛЬ «РАСПИСАНИЕ И БЛОКИРОВКИ»
-- ============================================================

-- ГрафикРаботы: рабочие интервалы с поддержкой нескольких перерывов в день (1 : 1)
CREATE TABLE work_schedules (
    schedule_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id          INTEGER NOT NULL UNIQUE REFERENCES masters(master_id) ON DELETE CASCADE,
    weekly_hours_json  TEXT NOT NULL,
    slot_step_min      INTEGER NOT NULL DEFAULT 30 CHECK (slot_step_min IN (15, 30, 60)),
    horizon_days       INTEGER NOT NULL DEFAULT 30 CHECK (horizon_days BETWEEN 1 AND 365),
    min_notice_min     INTEGER NOT NULL DEFAULT 60 CHECK (min_notice_min >= 0),
    cancel_limit_hours INTEGER NOT NULL DEFAULT 3 CHECK (cancel_limit_hours >= 0),
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- БлокировкаВремени: разовые закрытия слотов, выходные и отпуска мастера
CREATE TABLE time_blocks (
    block_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    schedule_id INTEGER NOT NULL REFERENCES work_schedules(schedule_id) ON DELETE CASCADE,
    start_at    TIMESTAMP NOT NULL,
    end_at      TIMESTAMP NOT NULL,
    reason      VARCHAR(24) NOT NULL DEFAULT 'personal'
                CHECK (reason IN ('personal', 'day_off', 'vacation', 'other')),
    note        TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_at > start_at)
);

CREATE INDEX idx_time_blocks_schedule_start ON time_blocks(schedule_id, start_at);

-- ============================================================
-- МОДУЛЬ «КЛИЕНТЫ, ЗАПИСИ И УВЕДОМЛЕНИЯ»
-- ============================================================

-- КарточкаКлиента: профиль клиента в клиентской базе конкретного мастера
CREATE TABLE client_cards (
    client_card_id INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id      INTEGER NOT NULL REFERENCES masters(master_id) ON DELETE CASCADE,
    account_id     INTEGER REFERENCES web_accounts(account_id) ON DELETE SET NULL,
    tg_user_id     BIGINT,
    display_name   VARCHAR(128) NOT NULL,
    phone          VARCHAR(20),
    consent_at     TIMESTAMP,
    birthday       VARCHAR(5),
    note           TEXT,
    is_banned      BOOLEAN NOT NULL DEFAULT 0,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX ux_client_cards_master_account
    ON client_cards(master_id, account_id) WHERE account_id IS NOT NULL;
CREATE UNIQUE INDEX ux_client_cards_master_tg
    ON client_cards(master_id, tg_user_id) WHERE tg_user_id IS NOT NULL;
CREATE INDEX idx_client_cards_master_phone ON client_cards(master_id, phone);

-- Запись: бронирование визита клиента к мастеру
CREATE TABLE bookings (
    booking_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    master_id          INTEGER NOT NULL REFERENCES masters(master_id) ON DELETE CASCADE,
    client_card_id     INTEGER NOT NULL REFERENCES client_cards(client_card_id) ON DELETE RESTRICT,
    start_at           TIMESTAMP NOT NULL,
    end_at             TIMESTAMP NOT NULL,
    total_duration_min INTEGER NOT NULL CHECK (total_duration_min > 0),
    total_price        INTEGER CHECK (total_price IS NULL OR total_price >= 0),
    status             VARCHAR(20) NOT NULL DEFAULT 'confirmed'
                       CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no_show', 'rejected', 'expired')),
    source             VARCHAR(16) NOT NULL DEFAULT 'web'
                       CHECK (source IN ('web', 'telegram', 'manual')),
    comment            TEXT,
    idem_key           VARCHAR(64) UNIQUE,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_at > start_at)
);

-- Защита от двойного бронирования одного активного окна у мастера
CREATE UNIQUE INDEX ux_bookings_active_slot
    ON bookings(master_id, start_at) WHERE status IN ('pending', 'confirmed');
CREATE INDEX idx_bookings_master_start ON bookings(master_id, start_at);
CREATE INDEX idx_bookings_client ON bookings(client_card_id, start_at);

-- УслугаЗаписи: связь M:N между записями и услугами (одиночные и комбо-визиты со снимком цены)
CREATE TABLE booking_services (
    booking_service_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id             INTEGER NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    service_id             INTEGER NOT NULL REFERENCES services(service_id) ON DELETE RESTRICT,
    service_title_snapshot VARCHAR(128) NOT NULL,
    duration_min_snapshot  INTEGER NOT NULL CHECK (duration_min_snapshot > 0),
    price_snapshot         INTEGER CHECK (price_snapshot IS NULL OR price_snapshot >= 0),
    UNIQUE (booking_id, service_id)
);

-- Уведомление: единая таблица для каналов web (УведомлениеНаСайте), email (Письмо), telegram (СообщениеTelegram)
CREATE TABLE notifications (
    notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id      INTEGER REFERENCES bookings(booking_id) ON DELETE SET NULL,
    account_id      INTEGER REFERENCES web_accounts(account_id) ON DELETE CASCADE,
    channel         VARCHAR(16) NOT NULL CHECK (channel IN ('web', 'email', 'telegram')),
    recipient_role  VARCHAR(16) NOT NULL CHECK (recipient_role IN ('client', 'master')),
    event_type      VARCHAR(32) NOT NULL
                    CHECK (event_type IN ('created', 'pending', 'confirmed', 'rescheduled', 'cancelled', 'rejected', 'reminder')),
    title           VARCHAR(160) NOT NULL,
    body            TEXT NOT NULL,
    delivery_status VARCHAR(16) NOT NULL DEFAULT 'pending'
                    CHECK (delivery_status IN ('pending', 'sent', 'failed')),
    is_read         BOOLEAN NOT NULL DEFAULT 0,
    action_link     VARCHAR(200),
    recipient_email VARCHAR(254),
    recipient_tg_id BIGINT,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at         TIMESTAMP
);

CREATE INDEX idx_notifications_account_read ON notifications(account_id, is_read, notification_id);
CREATE INDEX idx_notifications_booking ON notifications(booking_id);
CREATE INDEX idx_notifications_delivery ON notifications(channel, delivery_status);
