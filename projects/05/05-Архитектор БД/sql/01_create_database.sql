-- Campus Sport | PostgreSQL
-- Выполнить в пустой БД, например campus_sport. Скрипт создаёт схему campus_sport.
BEGIN;
CREATE SCHEMA campus_sport;
SET LOCAL search_path TO campus_sport, public;

-- Пользователи и авторизация
CREATE TABLE users (
    user_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name varchar(160) NOT NULL CHECK (btrim(full_name) <> ''),
    email varchar(254) NOT NULL UNIQUE CHECK (email = lower(btrim(email)) AND email <> ''),
    password_hash text NOT NULL,
    role varchar(12) NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'coach', 'admin')),
    status varchar(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'blocked')),
    student_number varchar(32) UNIQUE,
    study_group varchar(40),
    specialization varchar(120),
    phone varchar(32),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE account_activation_tokens (
    token_hash char(64) PRIMARY KEY CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    user_id integer NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    issued_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz NOT NULL DEFAULT (CURRENT_TIMESTAMP + interval '24 hours'),
    CHECK (expires_at = issued_at + interval '24 hours')
);

-- Каталог и расписание
CREATE TABLE sports (
    sport_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE CHECK (btrim(name) <> '')
);

CREATE TABLE venues (
    venue_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(120) NOT NULL UNIQUE CHECK (btrim(name) <> '')
);

CREATE TABLE sections (
    section_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sport_id integer NOT NULL REFERENCES sports(sport_id),
    coach_id integer REFERENCES users(user_id),
    name varchar(140) NOT NULL UNIQUE CHECK (btrim(name) <> ''),
    description text NOT NULL DEFAULT '',
    archived_at timestamptz
);

CREATE TABLE trainings (
    training_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    section_id integer NOT NULL REFERENCES sections(section_id),
    coach_id integer NOT NULL REFERENCES users(user_id),
    venue_id integer NOT NULL REFERENCES venues(venue_id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    max_participants integer NOT NULL CHECK (max_participants > 0),
    status varchar(12) NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'completed', 'canceled')),
    CHECK (ends_at > starts_at),
    -- Одноточечные диапазоны ID позволяют использовать GiST без расширений.
    CONSTRAINT no_venue_overlap EXCLUDE USING gist
        (int8range(venue_id, venue_id::bigint + 1) WITH =,
         tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status <> 'canceled'),
    CONSTRAINT no_coach_overlap EXCLUDE USING gist
        (int8range(coach_id, coach_id::bigint + 1) WITH =,
         tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status <> 'canceled'),
    CONSTRAINT no_section_overlap EXCLUDE USING gist
        (int8range(section_id, section_id::bigint + 1) WITH =,
         tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status <> 'canceled')
);

-- Запись и посещаемость
CREATE TABLE enrollments (
    training_id integer REFERENCES trainings(training_id),
    student_id integer REFERENCES users(user_id),
    booked_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (training_id, student_id)
);

CREATE TABLE attendance (
    training_id integer,
    student_id integer,
    marked_by integer NOT NULL REFERENCES users(user_id),
    present boolean NOT NULL,
    marked_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (training_id, student_id),
    FOREIGN KEY (training_id, student_id) REFERENCES enrollments(training_id, student_id)
);

-- Уведомления и аудит
CREATE TABLE notifications (
    notification_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users(user_id),
    training_id integer NOT NULL REFERENCES trainings(training_id),
    event_type varchar(24) NOT NULL
        CHECK (event_type IN ('booking_confirmed', 'training_reminder', 'training_changed', 'training_canceled')),
    message text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    scheduled_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_sent_at timestamptz,
    read_at timestamptz
);

CREATE TABLE security_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id integer REFERENCES users(user_id),
    target_user_id integer REFERENCES users(user_id),
    event_type varchar(24) NOT NULL
        CHECK (event_type IN ('login_ok', 'login_failed', 'password_changed', 'admin_action')),
    details text,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для каталога, расписания, личных записей и доставки уведомлений
CREATE INDEX ix_sections_sport ON sections (sport_id);
CREATE INDEX ix_sections_coach ON sections (coach_id);
CREATE INDEX ix_trainings_section_time ON trainings (section_id, starts_at);
CREATE INDEX ix_trainings_scheduled_time ON trainings (starts_at) WHERE status = 'scheduled';
CREATE INDEX ix_enrollments_student ON enrollments (student_id, training_id);
CREATE INDEX ix_notifications_user ON notifications (user_id, scheduled_at DESC);
CREATE INDEX ix_notifications_email_queue ON notifications (scheduled_at, notification_id)
    WHERE email_sent_at IS NULL;
CREATE INDEX ix_security_events_time ON security_events (occurred_at DESC);

-- Запись и отмена меняют строку тренировки, чтобы конкурирующие операции
-- проходили последовательно. При строгой изоляции возможен повтор транзакции.
CREATE FUNCTION guard_enrollment() RETURNS trigger
LANGUAGE plpgsql
SET search_path = campus_sport, pg_temp
AS $$
DECLARE
    training_row trainings%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Для изменения записи отмените её и запишитесь заново';
    END IF;

    UPDATE trainings
    SET max_participants = max_participants
    WHERE training_id = CASE WHEN TG_OP = 'INSERT' THEN NEW.training_id ELSE OLD.training_id END
    RETURNING * INTO training_row;

    IF NOT FOUND OR training_row.status <> 'scheduled'
        OR training_row.starts_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Запись и отмена доступны только до начала запланированной тренировки';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM users WHERE user_id = NEW.student_id AND role = 'student' AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Запись доступна активному студенту';
    END IF;

    IF EXISTS (
        SELECT 1 FROM enrollments WHERE training_id = NEW.training_id AND student_id = NEW.student_id
    ) THEN
        RAISE EXCEPTION 'Студент уже записан' USING ERRCODE = '23505';
    END IF;

    IF (SELECT count(*) FROM enrollments WHERE training_id = NEW.training_id)
        >= training_row.max_participants THEN
        RAISE EXCEPTION 'Свободных мест нет' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER guard_enrollment BEFORE INSERT OR UPDATE OR DELETE ON enrollments
    FOR EACH ROW EXECUTE FUNCTION guard_enrollment();

CREATE FUNCTION guard_capacity() RETURNS trigger
LANGUAGE plpgsql
SET search_path = campus_sport, pg_temp
AS $$
BEGIN
    IF NEW.max_participants < (
        SELECT count(*) FROM enrollments WHERE training_id = OLD.training_id
    ) THEN
        RAISE EXCEPTION 'Лимит ниже числа записанных студентов' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER guard_capacity BEFORE UPDATE ON trainings
    FOR EACH ROW WHEN (NEW.max_participants < OLD.max_participants)
    EXECUTE FUNCTION guard_capacity();

CREATE FUNCTION guard_attendance() RETURNS trigger
LANGUAGE plpgsql
SET search_path = campus_sport, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trainings t JOIN users u ON u.user_id = t.coach_id
        WHERE t.training_id = NEW.training_id AND t.status = 'completed'
          AND t.ends_at <= statement_timestamp() AND u.user_id = NEW.marked_by
          AND u.role = 'coach' AND u.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Посещаемость отмечает тренер после завершения занятия';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER guard_attendance BEFORE INSERT OR UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION guard_attendance();

CREATE VIEW training_availability AS
SELECT t.training_id, t.section_id, t.coach_id, t.venue_id,
       t.starts_at, t.ends_at, t.status, t.max_participants,
       occupied.booked,
       CASE WHEN t.status = 'scheduled' AND t.starts_at > statement_timestamp()
            THEN t.max_participants - occupied.booked ELSE 0 END AS free_places
FROM trainings t
CROSS JOIN LATERAL (
    SELECT count(*)::integer AS booked FROM enrollments e WHERE e.training_id = t.training_id
) occupied;

COMMIT;
