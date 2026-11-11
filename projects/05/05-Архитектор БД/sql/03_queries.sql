-- Campus Sport | Основные запросы
-- После 01 и 02. Все изменения ниже откатываются. В приложении используются
-- параметры запроса, ID из авторизованной сессии и проверка прав на операцию.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path TO campus_sport, public;
SET LOCAL TIME ZONE 'Europe/Moscow';

-- РЕГИСТРАЦИЯ, АКТИВАЦИЯ И ВХОД (ПИ-1.1–1.3)
WITH registered AS (
    INSERT INTO users (full_name, email, password_hash)
    VALUES ('Новый студент', lower(btrim('new@example.test')), 'fixture-only')
    RETURNING user_id
)
INSERT INTO account_activation_tokens (token_hash, user_id)
SELECT repeat('b', 64), user_id FROM registered;

-- Приложение передаёт SHA-256 от полученного токена. Успех возвращает ID.
WITH eligible AS MATERIALIZED (
    SELECT u.user_id
    FROM users u JOIN account_activation_tokens tok USING (user_id)
    WHERE tok.token_hash = repeat('b', 64) AND u.status = 'pending'
    FOR UPDATE OF u
), consumed AS (
    DELETE FROM account_activation_tokens tok USING eligible u
    WHERE tok.token_hash = repeat('b', 64) AND tok.user_id = u.user_id
      AND tok.expires_at > clock_timestamp()
    RETURNING tok.user_id
)
UPDATE users u SET status = 'active'
FROM consumed c WHERE u.user_id = c.user_id AND u.status = 'pending'
RETURNING u.user_id;

-- Хеш получает только сервер. Пароль сверяется в приложении (Argon2 или bcrypt).
SELECT user_id, full_name, role, password_hash FROM users
WHERE email = 'alexey@example.test' AND status = 'active';

UPDATE users SET study_group = 'ИТ-22'
WHERE email = 'alexey@example.test' AND role = 'student' AND status = 'active';

-- КАТАЛОГ И РАСПИСАНИЕ (ПИ-2.1–2.6)
SELECT s.section_id, s.name, sp.name AS sport, u.full_name AS coach, s.description,
       next_training.starts_at, next_training.free_places
FROM sections s
JOIN sports sp USING (sport_id)
LEFT JOIN users u ON u.user_id = s.coach_id
LEFT JOIN LATERAL (
    SELECT a.starts_at, a.free_places
    FROM training_availability a
    WHERE a.section_id = s.section_id AND a.status = 'scheduled'
      AND a.starts_at > statement_timestamp()
      AND extract(hour FROM a.starts_at) >= 16  -- пример фильтра по местному времени
    ORDER BY a.starts_at, a.training_id LIMIT 1
) next_training ON true
WHERE s.archived_at IS NULL AND (s.name ILIKE '%бол%' OR sp.name ILIKE '%бол%')
  AND next_training.starts_at IS NOT NULL
ORDER BY s.name;

SELECT s.name AS section, a.training_id, a.starts_at, a.ends_at,
       v.name AS venue, u.full_name AS coach, a.max_participants, a.free_places
FROM training_availability a
JOIN sections s USING (section_id)
JOIN venues v USING (venue_id)
JOIN users u ON u.user_id = a.coach_id
WHERE s.archived_at IS NULL AND a.status = 'scheduled'
  AND a.starts_at >= CURRENT_DATE AND a.starts_at < CURRENT_DATE + 7
ORDER BY a.starts_at, a.training_id;

-- ЗАПИСЬ, ЛИЧНОЕ РАСПИСАНИЕ И ОТМЕНА (ПИ-3.1–3.4)
-- Ошибки ограничений 23505 / 23514 отображаются как повторная запись / нет мест.
WITH booked AS (
    INSERT INTO enrollments (training_id, student_id)
    SELECT a.training_id, u.user_id
    FROM training_availability a
    JOIN sections s USING (section_id)
    CROSS JOIN users u
    WHERE u.email = 'alexey@example.test' AND s.name = 'Волейбол'
      AND s.archived_at IS NULL AND a.status = 'scheduled' AND a.starts_at > statement_timestamp()
    ORDER BY a.starts_at LIMIT 1
    RETURNING training_id, student_id
)
INSERT INTO notifications (user_id, training_id, event_type, message, scheduled_at)
SELECT r.user_id, b.training_id, n.event_type, n.message, n.scheduled_at
FROM booked b
JOIN trainings t USING (training_id)
CROSS JOIN LATERAL (VALUES
    (b.student_id, 'booking_confirmed'),
    (t.coach_id, 'booking_confirmed'),
    (b.student_id, 'training_reminder')
) AS r(user_id, event_type)
CROSS JOIN LATERAL (VALUES
    ('booking_confirmed', 'Создана запись на тренировку.', statement_timestamp()),
    ('training_reminder', 'Тренировка состоится завтра.', t.starts_at - interval '24 hours')
) AS n(event_type, message, scheduled_at)
WHERE r.event_type = n.event_type
  AND (n.event_type <> 'training_reminder' OR n.scheduled_at > statement_timestamp());

SELECT t.training_id, s.name AS section, t.starts_at, t.ends_at, v.name AS venue
FROM enrollments e
JOIN users u ON u.user_id = e.student_id
JOIN trainings t USING (training_id)
JOIN sections s USING (section_id)
JOIN venues v USING (venue_id)
WHERE u.email = 'alexey@example.test' AND t.status = 'scheduled' AND t.starts_at > statement_timestamp()
ORDER BY t.starts_at;

WITH removed AS (
    DELETE FROM enrollments e USING users u, trainings t, sections s
    WHERE e.student_id = u.user_id AND e.training_id = t.training_id AND t.section_id = s.section_id
      AND u.email = 'alexey@example.test' AND s.name = 'Волейбол'
      AND t.status = 'scheduled' AND t.starts_at::date = CURRENT_DATE + 2
    RETURNING e.training_id, e.student_id
)
DELETE FROM notifications n USING removed r
WHERE n.training_id = r.training_id AND n.user_id = r.student_id
  AND n.event_type = 'training_reminder' AND n.email_sent_at IS NULL;

-- РАСПИСАНИЕ И СПИСОК УЧАСТНИКОВ (ПИ-4.1–4.6, ПИ-6.5)
UPDATE sections s SET description = 'Техника подач и передач. Нужны форма и сменная обувь.'
FROM users u WHERE s.name = 'Волейбол' AND s.coach_id = u.user_id
  AND u.email = 'elena@example.test' AND u.role = 'coach' AND u.status = 'active';

INSERT INTO trainings (section_id, coach_id, venue_id, starts_at, ends_at, max_participants)
SELECT s.section_id, u.user_id, v.venue_id, CURRENT_DATE + 9 + time '18:00',
       CURRENT_DATE + 9 + time '19:30', 12
FROM sections s JOIN users u ON u.user_id = s.coach_id CROSS JOIN venues v
WHERE s.name = 'Волейбол' AND s.archived_at IS NULL AND v.name = 'Зал № 2'
  AND u.email = 'elena@example.test' AND u.role = 'coach' AND u.status = 'active';

-- Перенос и уведомления в одной транзакции. При конфликте PostgreSQL вернёт 23P01.
-- Отдельная команда блокировки даёт следующей команде свежий снимок записей.
SELECT t.training_id
FROM trainings t JOIN sections s USING (section_id)
WHERE s.name = 'Баскетбол' AND t.status = 'scheduled' AND t.starts_at::date = CURRENT_DATE + 3
FOR NO KEY UPDATE OF t;

WITH changed AS (
    UPDATE trainings t
    SET starts_at = t.starts_at + interval '1 hour',
        ends_at = t.ends_at + interval '1 hour',
        max_participants = 18
    FROM sections s, users c
    WHERE t.section_id = s.section_id AND t.coach_id = c.user_id AND s.coach_id = c.user_id
      AND s.name = 'Баскетбол' AND s.archived_at IS NULL
      AND c.email = 'dmitry@example.test' AND c.role = 'coach' AND c.status = 'active'
      AND t.status = 'scheduled' AND t.starts_at::date = CURRENT_DATE + 3
    RETURNING t.training_id, t.starts_at
), rescheduled AS (
    UPDATE notifications n
    SET scheduled_at = c.starts_at - interval '24 hours'
    FROM changed c
    WHERE n.training_id = c.training_id AND n.event_type = 'training_reminder'
      AND n.email_sent_at IS NULL
)
INSERT INTO notifications (user_id, training_id, event_type, message)
SELECT e.student_id, c.training_id, 'training_changed', 'Время тренировки изменилось.'
FROM changed c JOIN enrollments e USING (training_id);

SELECT t.training_id, u.full_name AS student, u.study_group, e.booked_at
FROM trainings t
JOIN sections s USING (section_id)
JOIN users c ON c.user_id = s.coach_id
JOIN enrollments e USING (training_id)
JOIN users u ON u.user_id = e.student_id
WHERE s.name = 'Волейбол' AND t.starts_at::date = CURRENT_DATE + 2
  AND c.email = 'elena@example.test' AND c.role = 'coach' AND c.status = 'active'
ORDER BY u.full_name;

-- Отмена занятия сохраняет записи для истории и снимает ожидающие напоминания.
SELECT t.training_id
FROM trainings t JOIN sections s USING (section_id)
WHERE s.name = 'Волейбол' AND t.status = 'scheduled' AND t.starts_at::date = CURRENT_DATE + 5
FOR NO KEY UPDATE OF t;

WITH canceled AS (
    UPDATE trainings t SET status = 'canceled'
    FROM sections s, users c
    WHERE t.section_id = s.section_id AND s.coach_id = c.user_id
      AND t.coach_id = c.user_id AND c.email = 'elena@example.test'
      AND c.role = 'coach' AND c.status = 'active' AND s.name = 'Волейбол'
      AND t.status = 'scheduled' AND t.starts_at::date = CURRENT_DATE + 5
    RETURNING t.training_id
), removed AS (
    DELETE FROM notifications n USING canceled c
    WHERE n.training_id = c.training_id AND n.event_type = 'training_reminder'
      AND n.email_sent_at IS NULL
)
INSERT INTO notifications (user_id, training_id, event_type, message)
SELECT e.student_id, c.training_id, 'training_canceled', 'Тренировка отменена.'
FROM canceled c JOIN enrollments e USING (training_id);

-- ПОСЕЩАЕМОСТЬ И ИСТОРИЯ (ПИ-5.1–5.4)
INSERT INTO attendance (training_id, student_id, marked_by, present)
SELECT t.training_id, e.student_id, c.user_id, true
FROM trainings t JOIN sections s USING (section_id)
JOIN enrollments e USING (training_id)
JOIN users u ON u.user_id = e.student_id
JOIN users c ON c.user_id = t.coach_id
WHERE s.name = 'Волейбол' AND t.status = 'completed'
  AND t.starts_at::date = CURRENT_DATE - 7
  AND c.email = 'elena@example.test' AND u.email = 'alexey@example.test'
ON CONFLICT (training_id, student_id) DO UPDATE
SET present = excluded.present, marked_by = excluded.marked_by, marked_at = excluded.marked_at;

SELECT t.starts_at, s.name AS section, u.full_name AS student, a.present, a.marked_at
FROM enrollments e
JOIN trainings t USING (training_id)
JOIN sections s USING (section_id)
JOIN users u ON u.user_id = e.student_id
LEFT JOIN attendance a USING (training_id, student_id)
WHERE t.status = 'completed' AND u.email = 'alexey@example.test'
ORDER BY t.starts_at DESC;

SELECT t.starts_at, s.name AS section, u.full_name AS student, a.present
FROM trainings t
JOIN sections s USING (section_id)
JOIN users c ON c.user_id = s.coach_id
JOIN enrollments e USING (training_id)
JOIN users u ON u.user_id = e.student_id
LEFT JOIN attendance a USING (training_id, student_id)
WHERE t.status = 'completed' AND c.email = 'elena@example.test'
  AND c.role = 'coach' AND c.status = 'active'
ORDER BY t.starts_at DESC, u.full_name;

-- АДМИНИСТРИРОВАНИЕ (ПИ-6.1–6.5)
SELECT user_id, full_name, email, role, status FROM users ORDER BY full_name;

INSERT INTO sections (sport_id, name, description)
SELECT sport_id, 'Баскетбол для начинающих', 'Вводная группа.'
FROM sports WHERE name = 'Баскетбол';

UPDATE sections s SET coach_id = u.user_id
FROM users u
WHERE s.name = 'Баскетбол для начинающих' AND u.email = 'dmitry@example.test'
  AND u.role = 'coach' AND u.status = 'active';

UPDATE sections SET archived_at = statement_timestamp()
WHERE name = 'Баскетбол для начинающих'
  AND NOT EXISTS (
      SELECT 1 FROM trainings t WHERE t.section_id = sections.section_id AND t.status = 'scheduled'
        AND t.ends_at > statement_timestamp()
  );

WITH updated AS (
    UPDATE users u SET status = 'blocked'
    WHERE u.email = 'vera@example.test' AND u.role = 'student'
    RETURNING u.user_id
), revoked AS (
    DELETE FROM account_activation_tokens tok USING updated u WHERE tok.user_id = u.user_id
)
INSERT INTO security_events (actor_id, target_user_id, event_type, details)
SELECT a.user_id, u.user_id, 'admin_action', 'Учётная запись заблокирована'
FROM updated u CROSS JOIN users a
WHERE a.email = 'maria@example.test' AND a.role = 'admin' AND a.status = 'active';

-- Смена роли с журналированием. Назначенного тренера сначала переназначают.
WITH admin_actor AS (
    SELECT user_id FROM users WHERE email = 'maria@example.test' AND role = 'admin' AND status = 'active'
), updated AS (
    UPDATE users u SET role = 'coach'
    FROM admin_actor a
    WHERE u.email = 'ilya@example.test' AND u.role = 'student'
      AND NOT EXISTS (SELECT 1 FROM sections s WHERE s.coach_id = u.user_id AND s.archived_at IS NULL)
    RETURNING u.user_id, a.user_id AS actor_id
)
INSERT INTO security_events (actor_id, target_user_id, event_type, details)
SELECT actor_id, user_id, 'admin_action', 'Роль изменена со студента на тренера'
FROM updated;

-- УВЕДОМЛЕНИЯ (НФТ §9)
SELECT notification_id, message, scheduled_at, read_at
FROM notifications n JOIN users u USING (user_id)
WHERE u.email = 'alexey@example.test' AND n.scheduled_at <= statement_timestamp()
ORDER BY n.scheduled_at DESC, n.notification_id DESC;

SELECT notification_id, user_id, event_type, message
FROM notifications
WHERE email_sent_at IS NULL AND scheduled_at <= statement_timestamp()
ORDER BY scheduled_at, notification_id LIMIT 20;

ROLLBACK;
