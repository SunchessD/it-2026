-- Campus Sport | Демонстрационные данные для пустой схемы
BEGIN;
SET LOCAL search_path TO campus_sport, public;
SET LOCAL TIME ZONE 'Europe/Moscow';

-- Тестовые значения password_hash не предназначены для входа в приложение.
INSERT INTO users (full_name, email, password_hash, role, status, student_number, study_group, specialization, phone)
VALUES
    ('Мария Орлова', 'maria@example.test', 'fixture-only', 'admin', 'active', NULL, NULL, NULL, NULL),
    ('Елена Соколова', 'elena@example.test', 'fixture-only', 'coach', 'active', NULL, NULL, 'Волейбол', '+7 900 000-00-01'),
    ('Дмитрий Волков', 'dmitry@example.test', 'fixture-only', 'coach', 'active', NULL, NULL, 'Баскетбол', '+7 900 000-00-02'),
    ('Ольга Белова', 'olga@example.test', 'fixture-only', 'coach', 'active', NULL, NULL, 'Настольный теннис', '+7 900 000-00-03'),
    ('Алексей Смирнов', 'alexey@example.test', 'fixture-only', 'student', 'active', 'СТ-26001', 'ИТ-21', NULL, NULL),
    ('Анна Кузнецова', 'anna@example.test', 'fixture-only', 'student', 'active', 'СТ-26002', 'ИТ-21', NULL, NULL),
    ('Илья Морозов', 'ilya@example.test', 'fixture-only', 'student', 'active', 'СТ-26003', 'ИВТ-22', NULL, NULL),
    ('Вера Лебедева', 'vera@example.test', 'fixture-only', 'student', 'pending', NULL, NULL, NULL, NULL);

INSERT INTO account_activation_tokens (token_hash, user_id)
SELECT repeat('a', 64), user_id FROM users WHERE email = 'vera@example.test';

INSERT INTO sports (name) VALUES ('Волейбол'), ('Баскетбол'), ('Настольный теннис');
INSERT INTO venues (name) VALUES ('Зал № 1'), ('Зал № 2'), ('Малый зал');

INSERT INTO sections (sport_id, coach_id, name, description)
SELECT s.sport_id, u.user_id, s.name, demo.description
FROM (VALUES
    ('Волейбол', 'elena@example.test', 'Техника подач и передач. Нужны спортивная форма и сменная обувь.'),
    ('Баскетбол', 'dmitry@example.test', 'Броски, командная тактика и игровые упражнения.'),
    ('Настольный теннис', 'olga@example.test', 'Техника подачи и розыгрыша. Ракетки выдаются в зале.')
) AS demo(sport, coach_email, description)
JOIN sports s ON s.name = demo.sport
JOIN users u ON u.email = demo.coach_email;

-- Сначала создаём будущие занятия и записи. После загрузки часть занятий
-- переносим в прошлое, чтобы заполнить журнал через обычные ограничения БД.
INSERT INTO trainings (section_id, coach_id, venue_id, starts_at, ends_at, max_participants)
SELECT s.section_id, s.coach_id, v.venue_id,
       (CURRENT_DATE + demo.days + demo.start_time)::timestamptz,
       (CURRENT_DATE + demo.days + demo.end_time)::timestamptz, demo.capacity
FROM (VALUES
    ('Волейбол', 'Зал № 2', 2, time '18:00', time '19:30',  3),
    ('Волейбол', 'Зал № 2', 5, time '18:00', time '19:30',  1),
    ('Баскетбол', 'Зал № 1', 3, time '17:00', time '18:30', 16),
    ('Настольный теннис', 'Малый зал', 4, time '16:00', time '17:00', 1),
    ('Волейбол', 'Зал № 2', 7, time '18:00', time '19:30', 20),
    ('Баскетбол', 'Зал № 1', 8, time '17:00', time '18:30', 16)
) AS demo(section_name, venue_name, days, start_time, end_time, capacity)
JOIN sections s ON s.name = demo.section_name
JOIN venues v ON v.name = demo.venue_name;

INSERT INTO enrollments (training_id, student_id, booked_at)
SELECT t.training_id, u.user_id,
       CASE WHEN demo.days = 7 THEN CURRENT_TIMESTAMP - interval '10 days' ELSE CURRENT_TIMESTAMP END
FROM (VALUES
    ('Волейбол', 2, 'anna@example.test'),
    ('Волейбол', 5, 'anna@example.test'),
    ('Баскетбол', 3, 'alexey@example.test'),
    ('Настольный теннис', 4, 'ilya@example.test'),
    ('Волейбол', 7, 'alexey@example.test'),
    ('Волейбол', 7, 'anna@example.test')
) AS demo(section_name, days, email)
JOIN sections s ON s.name = demo.section_name
JOIN trainings t ON t.section_id = s.section_id AND t.starts_at::date = CURRENT_DATE + demo.days
JOIN users u ON u.email = demo.email;

UPDATE trainings
SET starts_at = starts_at - interval '14 days',
    ends_at = ends_at - interval '14 days',
    status = 'completed'
WHERE starts_at::date = CURRENT_DATE + 7;

UPDATE trainings SET status = 'canceled' WHERE starts_at::date = CURRENT_DATE + 8;

INSERT INTO attendance (training_id, student_id, marked_by, present, marked_at)
SELECT e.training_id, e.student_id, t.coach_id, u.email = 'alexey@example.test',
       t.ends_at + interval '10 minutes'
FROM enrollments e
JOIN trainings t USING (training_id)
JOIN users u ON u.user_id = e.student_id
WHERE t.status = 'completed';

INSERT INTO notifications (user_id, training_id, event_type, message, email_sent_at, read_at)
SELECT e.student_id, e.training_id, 'booking_confirmed', 'Вы записаны на тренировку.',
       CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM enrollments e JOIN trainings t USING (training_id)
WHERE t.status = 'scheduled';

INSERT INTO notifications (user_id, training_id, event_type, message, scheduled_at)
SELECT e.student_id, e.training_id, 'training_reminder', 'Тренировка состоится завтра.',
       t.starts_at - interval '24 hours'
FROM enrollments e JOIN trainings t USING (training_id)
WHERE t.status = 'scheduled';

INSERT INTO security_events (actor_id, target_user_id, event_type, details)
SELECT user_id, user_id, 'login_ok', 'Демонстрационная запись о входе'
FROM users WHERE email = 'alexey@example.test';

-- Контроль количества загруженных строк (ожидается 8/1/3/3/3/6/6/2/8/1).
SELECT 'users' AS table_name, count(*) AS row_count FROM users
UNION ALL SELECT 'account_activation_tokens', count(*) FROM account_activation_tokens
UNION ALL SELECT 'sports', count(*) FROM sports
UNION ALL SELECT 'venues', count(*) FROM venues
UNION ALL SELECT 'sections', count(*) FROM sections
UNION ALL SELECT 'trainings', count(*) FROM trainings
UNION ALL SELECT 'enrollments', count(*) FROM enrollments
UNION ALL SELECT 'attendance', count(*) FROM attendance
UNION ALL SELECT 'notifications', count(*) FROM notifications
UNION ALL SELECT 'security_events', count(*) FROM security_events;

COMMIT;
