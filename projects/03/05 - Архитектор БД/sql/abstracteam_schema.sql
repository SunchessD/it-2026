-- Abstracteam: физическая модель БД (проектная версия)
-- СУБД: PostgreSQL
-- В модели ровно 11 таблиц. Справочники и связующие сущности не расширяют этот состав.
-- Перед применением на реальной БД проверьте допущения из abstracteam_schema_notes.md.

BEGIN;

-- 1. Пользователи
CREATE TABLE users (
    user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     VARCHAR(150) NOT NULL,
    email         VARCHAR(254) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20) NOT NULL DEFAULT 'student',
    status        VARCHAR(20) NOT NULL DEFAULT 'inactive',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_role
        CHECK (role IN ('student', 'admin')),
    CONSTRAINT chk_users_status
        CHECK (status IN ('inactive', 'active', 'blocked')),
    CONSTRAINT chk_users_full_name
        CHECK (length(btrim(full_name)) > 0),
    CONSTRAINT chk_users_email
        CHECK (length(btrim(email)) > 0)
);

-- Email сравнивается без учёта регистра.
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));

-- 2. Профили студентов. Первичный ключ одновременно является внешним ключом.
CREATE TABLE student_profiles (
    user_id    BIGINT PRIMARY KEY,
    about      TEXT,
    telegram   VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_student_profiles_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
);

-- 3. Токены активации: не более одной записи токена на пользователя.
CREATE TABLE account_activation_tokens (
    activation_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             BIGINT NOT NULL UNIQUE,
    token_hash          VARCHAR(255) NOT NULL UNIQUE,
    expires_at          TIMESTAMPTZ NOT NULL,
    used_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_activation_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT chk_activation_expiration
        CHECK (expires_at > created_at),
    CONSTRAINT chk_activation_used_at
        CHECK (used_at IS NULL OR used_at >= created_at)
);

-- 4. Справочник тегов.
CREATE TABLE tags (
    tag_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    category   VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_tags_category
        CHECK (category IN ('specialty', 'study_direction', 'technology_stack', 'interest')),
    CONSTRAINT chk_tags_name
        CHECK (length(btrim(name)) > 0),
    CONSTRAINT uq_tags_category_name UNIQUE (category, name)
);

-- 5. Связь профилей пользователей с тегами.
CREATE TABLE user_tags (
    user_id    BIGINT NOT NULL,
    tag_id     BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_tags PRIMARY KEY (user_id, tag_id),
    CONSTRAINT fk_user_tags_profile
        FOREIGN KEY (user_id) REFERENCES student_profiles (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_tags_tag
        FOREIGN KEY (tag_id) REFERENCES tags (tag_id) ON DELETE RESTRICT
);

-- 6. Мероприятия.
CREATE TABLE events (
    event_id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                     VARCHAR(200) NOT NULL,
    event_type               VARCHAR(30) NOT NULL,
    topic                    TEXT,
    description              TEXT,
    application_deadline     DATE NOT NULL,
    start_date               DATE NOT NULL,
    end_date                 DATE NOT NULL,
    participation_conditions TEXT,
    source_url               TEXT,
    status                   VARCHAR(20) NOT NULL DEFAULT 'published',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_events_type
        CHECK (event_type IN ('conference', 'hackathon', 'case_championship', 'other')),
    CONSTRAINT chk_events_status
        CHECK (status IN ('published', 'unpublished', 'archived')),
    CONSTRAINT chk_events_name
        CHECK (length(btrim(name)) > 0),
    CONSTRAINT chk_events_dates
        CHECK (end_date >= start_date)
);

-- 7. Заявки на поиск команды. event_id NULL означает общую заявку.
CREATE TABLE applications (
    application_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id        BIGINT,
    author_id       BIGINT NOT NULL,
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    available_places INTEGER NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    published_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_applications_event
        FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE RESTRICT,
    CONSTRAINT fk_applications_author
        FOREIGN KEY (author_id) REFERENCES student_profiles (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_applications_status
        CHECK (status IN ('open', 'closed')),
    CONSTRAINT chk_applications_available_places
        CHECK (available_places >= 0),
    CONSTRAINT chk_applications_title
        CHECK (length(btrim(title)) > 0)
);

-- 8. Теги, необходимые для заявки.
CREATE TABLE application_tags (
    application_id BIGINT NOT NULL,
    tag_id         BIGINT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_application_tags PRIMARY KEY (application_id, tag_id),
    CONSTRAINT fk_application_tags_application
        FOREIGN KEY (application_id) REFERENCES applications (application_id) ON DELETE CASCADE,
    CONSTRAINT fk_application_tags_tag
        FOREIGN KEY (tag_id) REFERENCES tags (tag_id) ON DELETE RESTRICT
);

-- 9. Отклики на заявки.
CREATE TABLE responses (
    response_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL,
    user_id        BIGINT NOT NULL,
    message        TEXT,
    status         VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_responses_application
        FOREIGN KEY (application_id) REFERENCES applications (application_id) ON DELETE CASCADE,
    CONSTRAINT fk_responses_user
        FOREIGN KEY (user_id) REFERENCES student_profiles (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_responses_status
        CHECK (status IN ('pending', 'accepted', 'rejected')),
    CONSTRAINT uq_responses_application_user UNIQUE (application_id, user_id)
);

-- 10. Уведомления. Связи с мероприятиями, заявками и откликами намеренно отсутствуют.
CREATE TABLE notifications (
    notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         BIGINT NOT NULL,
    category        VARCHAR(30) NOT NULL,
    channel         VARCHAR(20) NOT NULL,
    title           VARCHAR(200) NOT NULL,
    body            TEXT NOT NULL,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notifications_profile
        FOREIGN KEY (user_id) REFERENCES student_profiles (user_id) ON DELETE CASCADE,
    CONSTRAINT chk_notifications_category
        CHECK (category IN ('new_application', 'response_activity', 'event_changed')),
    CONSTRAINT chk_notifications_channel
        CHECK (channel IN ('email', 'in_app'))
);

-- 11. Настройки уведомлений по каналу и категории.
-- category='all' допускается только для канала email и представляет общий переключатель рассылки.
CREATE TABLE notification_settings (
    user_id    BIGINT NOT NULL,
    channel    VARCHAR(20) NOT NULL,
    category   VARCHAR(30) NOT NULL,
    is_enabled BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_notification_settings PRIMARY KEY (user_id, channel, category),
    CONSTRAINT fk_notification_settings_profile
        FOREIGN KEY (user_id) REFERENCES student_profiles (user_id) ON DELETE CASCADE,
    CONSTRAINT chk_notification_settings_channel
        CHECK (channel IN ('email', 'in_app')),
    CONSTRAINT chk_notification_settings_category
        CHECK (
            category IN ('new_application', 'response_activity', 'event_changed')
            OR (category = 'all' AND channel = 'email')
        )
);

-- Индексы для основных сценариев поиска и просмотра.
CREATE INDEX ix_user_tags_tag_id ON user_tags (tag_id);
CREATE INDEX ix_events_status_deadline ON events (status, application_deadline);
CREATE INDEX ix_events_start_date ON events (start_date);
CREATE INDEX ix_applications_event_status ON applications (event_id, status);
CREATE INDEX ix_applications_author_id ON applications (author_id);
CREATE INDEX ix_application_tags_tag_id ON application_tags (tag_id);
CREATE INDEX ix_responses_user_id ON responses (user_id);
CREATE INDEX ix_responses_application_status ON responses (application_id, status);
CREATE INDEX ix_notifications_user_created ON notifications (user_id, created_at DESC);
CREATE INDEX ix_notifications_unread ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;

-- Универсальная функция актуализации updated_at.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_student_profiles_updated_at
BEFORE UPDATE ON student_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_activation_tokens_updated_at
BEFORE UPDATE ON account_activation_tokens
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tags_updated_at
BEFORE UPDATE ON tags
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_events_updated_at
BEFORE UPDATE ON events
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_applications_updated_at
BEFORE UPDATE ON applications
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_responses_updated_at
BEFORE UPDATE ON responses
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_notifications_updated_at
BEFORE UPDATE ON notifications
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_notification_settings_updated_at
BEFORE UPDATE ON notification_settings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- При нулевом количестве свободных мест заявка автоматически закрывается.
CREATE OR REPLACE FUNCTION close_application_when_no_places()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.available_places = 0 THEN
        NEW.status := 'closed';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_applications_close_when_no_places
BEFORE INSERT OR UPDATE OF available_places ON applications
FOR EACH ROW EXECUTE FUNCTION close_application_when_no_places();

-- Нельзя откликнуться на собственную или закрытую заявку.
CREATE OR REPLACE FUNCTION validate_response_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_author_id BIGINT;
    v_application_status VARCHAR(20);
BEGIN
    SELECT author_id, status
      INTO v_author_id, v_application_status
      FROM applications
     WHERE application_id = NEW.application_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % does not exist', NEW.application_id;
    END IF;

    IF v_author_id = NEW.user_id THEN
        RAISE EXCEPTION 'A user cannot respond to their own application';
    END IF;

    IF v_application_status <> 'open' THEN
        RAISE EXCEPTION 'Responses are accepted only for open applications';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_responses_validate_before_insert
BEFORE INSERT ON responses
FOR EACH ROW EXECUTE FUNCTION validate_response_submission();

-- При переводе мероприятия в архив все открытые заявки по нему закрываются.
CREATE OR REPLACE FUNCTION close_applications_when_event_archived()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'archived' AND OLD.status IS DISTINCT FROM NEW.status THEN
        UPDATE applications
           SET status = 'closed'
         WHERE event_id = NEW.event_id
           AND status = 'open';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_events_close_applications_on_archive
AFTER UPDATE OF status ON events
FOR EACH ROW EXECUTE FUNCTION close_applications_when_event_archived();

COMMIT;
