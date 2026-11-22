-- ============================================================
-- Веб-приложение "Мой список покупок"
-- Создание базы данных (PostgreSQL)
-- Автор: Ин Бан
-- ============================================================
-- Скрипт предназначен для выполнения в новой базе PostgreSQL.

BEGIN;

-- ============================================================
-- МОДУЛЬ "ПОЛЬЗОВАТЕЛИ И АВТОРИЗАЦИЯ"
-- ============================================================

-- Пользователи системы
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'user',
    status VARCHAR(20) NOT NULL DEFAULT 'inactive',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_role_check CHECK (role IN ('user', 'admin')),
    CONSTRAINT users_status_check CHECK (status IN ('inactive', 'active', 'blocked'))
);

-- Одноразовые токены активации учетной записи
CREATE TABLE account_activation_tokens (
    token VARCHAR(255) PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- МОДУЛЬ "СПИСКИ ПОКУПОК"
-- ============================================================

-- Общий справочник категорий товаров
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);

-- Списки покупок, созданные пользователями
CREATE TABLE shopping_lists (
    list_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT shopping_lists_unique_name_per_user UNIQUE (user_id, name)
);

-- Товары в списках покупок
CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    list_id INT NOT NULL REFERENCES shopping_lists(list_id) ON DELETE CASCADE,
    category_id INT REFERENCES categories(category_id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    quantity NUMERIC(10, 2) NOT NULL DEFAULT 1,
    unit VARCHAR(30) NOT NULL DEFAULT 'шт.',
    is_purchased BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    purchased_at TIMESTAMPTZ,
    CONSTRAINT items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT items_purchase_time_check
        CHECK (purchased_at IS NULL OR is_purchased = TRUE)
);

-- ============================================================
-- АВТОМАТИЧЕСКОЕ ОБНОВЛЕНИЕ updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_shopping_lists_updated_at
BEFORE UPDATE ON shopping_lists
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- ИНДЕКСЫ ДЛЯ ОСНОВНЫХ СЦЕНАРИЕВ РАБОТЫ
-- ============================================================

CREATE INDEX idx_activation_tokens_user
    ON account_activation_tokens(user_id);

CREATE INDEX idx_shopping_lists_user_updated
    ON shopping_lists(user_id, updated_at DESC);

CREATE INDEX idx_items_list_status
    ON items(list_id, is_purchased);

CREATE INDEX idx_items_category
    ON items(category_id);

CREATE INDEX idx_items_name
    ON items(name);

COMMIT;
