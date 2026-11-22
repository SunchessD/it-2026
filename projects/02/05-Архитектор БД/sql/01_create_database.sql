-- ============================================================
-- Веб-платформа для интерактивного изучения методов
-- предиктивного анализа (ML Platform)
-- Создание базы данных (PostgreSQL 14+)
-- ============================================================

DROP TABLE IF EXISTS trained_models, experiment_metrics, experiment_settings,
    experiments, datasets, theory_materials, algorithms,
    account_activation_tokens, users CASCADE;

-- ============================================================
-- МОДУЛЬ "ПОЛЬЗОВАТЕЛИ И АВТОРИЗАЦИЯ"
-- ============================================================

-- Студенты (зарегистрированные пользователи).
-- Гость ничего не хранит в БД, поэтому отдельной таблицы для него нет.
CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,                 -- bcrypt / Argon2 (НФТ)
    status        VARCHAR(20)  NOT NULL DEFAULT 'inactive'
                  CHECK (status IN ('inactive', 'active')),
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Токены из письма для активации учётной записи
CREATE TABLE account_activation_tokens (
    token      VARCHAR(64) PRIMARY KEY,
    user_id    INT         NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    expires_at TIMESTAMP   NOT NULL
);

CREATE INDEX idx_tokens_user ON account_activation_tokens(user_id);

-- ============================================================
-- МОДУЛЬ "ТЕОРЕТИЧЕСКИЕ МАТЕРИАЛЫ"
-- ============================================================

-- Алгоритмы (справочник, 4 записи)
CREATE TABLE algorithms (
    algorithm_id SERIAL PRIMARY KEY,
    code         VARCHAR(50)  NOT NULL UNIQUE,           -- имя в API: 'knn', 'random_forest' ...
    name         VARCHAR(100) NOT NULL UNIQUE,
    task_type    VARCHAR(20)  NOT NULL
                 CHECK (task_type IN ('regression', 'classification', 'both'))
);

-- Теоретические материалы: страницы методов и справочник метрик
CREATE TABLE theory_materials (
    material_id  SERIAL PRIMARY KEY,
    section      VARCHAR(20)  NOT NULL CHECK (section IN ('method', 'metrics')),
    algorithm_id INT          REFERENCES algorithms(algorithm_id) ON DELETE SET NULL,
    title        VARCHAR(255) NOT NULL,
    content      TEXT         NOT NULL,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- у страницы метода есть алгоритм, у страницы справочника метрик — нет
    CHECK ((section = 'method') = (algorithm_id IS NOT NULL))
);

-- ============================================================
-- МОДУЛЬ "ЭКСПЕРИМЕНТЫ"
-- ============================================================

-- Наборы данных (CSV), загруженные студентами.
-- Сам файл лежит на диске сервера, в БД — путь к нему.
CREATE TABLE datasets (
    dataset_id  SERIAL PRIMARY KEY,
    user_id     INT          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,                   -- имя файла
    description TEXT,
    file_path   VARCHAR(500) NOT NULL UNIQUE,
    file_size   BIGINT       NOT NULL
                CHECK (file_size > 0 AND file_size <= 104857600),  -- до 100 МБ (НФТ)
    uploaded_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_datasets_user ON datasets(user_id);

-- Эксперименты. Запись создаётся при запуске обучения (status = 'running')
-- и дополняется по завершении (finished_at, status, метрики, модель).
CREATE TABLE experiments (
    experiment_id   SERIAL PRIMARY KEY,
    user_id         INT          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    dataset_id      INT          NOT NULL REFERENCES datasets(dataset_id) ON DELETE RESTRICT,
    algorithm_id    INT          NOT NULL REFERENCES algorithms(algorithm_id) ON DELETE RESTRICT,
    task_type       VARCHAR(20)  NOT NULL
                    CHECK (task_type IN ('regression', 'classification')),
    target_column   VARCHAR(255) NOT NULL,
    feature_columns TEXT[]       NOT NULL CHECK (cardinality(feature_columns) > 0),
    status          VARCHAR(20)  NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running', 'completed', 'failed')),
    started_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at     TIMESTAMP,
    error_message   TEXT,
    plot_data       JSONB,                               -- данные для графиков / матрицы ошибок
    CHECK (NOT (target_column = ANY (feature_columns))),
    CHECK (finished_at IS NULL OR finished_at >= started_at),
    CHECK ((status = 'running') = (finished_at IS NULL))
);

-- история экспериментов студента (сортировка по дате, фильтры)
CREATE INDEX idx_experiments_user_date ON experiments(user_id, started_at DESC);
CREATE INDEX idx_experiments_user_algorithm ON experiments(user_id, algorithm_id);
CREATE INDEX idx_experiments_dataset ON experiments(dataset_id);

-- Настройки эксперимента: значения гиперпараметров алгоритма
CREATE TABLE experiment_settings (
    setting_id    SERIAL PRIMARY KEY,
    experiment_id INT          NOT NULL REFERENCES experiments(experiment_id) ON DELETE CASCADE,
    param_name    VARCHAR(100) NOT NULL,
    param_value   VARCHAR(255) NOT NULL,
    UNIQUE (experiment_id, param_name)
);

-- Результаты эксперимента: значения метрик качества
CREATE TABLE experiment_metrics (
    result_id     SERIAL PRIMARY KEY,
    experiment_id INT          NOT NULL REFERENCES experiments(experiment_id) ON DELETE CASCADE,
    metric_name   VARCHAR(50)  NOT NULL,
    metric_value  DOUBLE PRECISION NOT NULL,
    UNIQUE (experiment_id, metric_name)
);

-- Обученная модель (не более одной на эксперимент).
-- Хранится 30 дней, затем запись и файл удаляются, метрики остаются (НФТ).
CREATE TABLE trained_models (
    model_id      SERIAL PRIMARY KEY,
    experiment_id INT          NOT NULL UNIQUE
                  REFERENCES experiments(experiment_id) ON DELETE CASCADE,
    file_path     VARCHAR(500) NOT NULL UNIQUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at    TIMESTAMP    GENERATED ALWAYS AS (created_at + INTERVAL '30 days') STORED
);

CREATE INDEX idx_trained_models_expires ON trained_models(expires_at);
