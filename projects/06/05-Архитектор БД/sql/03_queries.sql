-- ============================================================
-- Основные запросы для системы управления заданиями студентов
-- ============================================================


-- ============================================================
-- 1. СТУДЕНТЫ
-- ============================================================

-- Вывести список студентов (без хешей паролей)
SELECT student_id, name, email, created_at
FROM students
ORDER BY name;

-- Найти студента по электронной почте
SELECT student_id, name, email
FROM students
WHERE email = 'anna@example.org';

-- Пример регистрации нового студента.
-- Значение password_hash должно быть получено безопасным
-- алгоритмом хеширования в приложении.
-- INSERT INTO students (student_id, name, email, password_hash)
-- VALUES (
--     '00000000-0000-4000-8000-000000000006',
--     'Новый студент', 'new@example.org', '<password_hash>'
-- );

-- ============================================================
-- 2. ГРУППЫ И УЧАСТНИКИ
-- ============================================================

-- Список групп конкретного студента и его роль в каждой группе
SELECT g.group_id, g.name AS group_name, gm.role, gm.joined_at
FROM group_members gm
JOIN groups g ON g.group_id = gm.group_id
WHERE gm.student_id = '00000000-0000-4000-8000-000000000002'
ORDER BY g.name;

-- Список участников конкретной группы
SELECT s.student_id, s.name AS student_name, gm.role, gm.joined_at
FROM group_members gm
JOIN students s ON s.student_id = gm.student_id
WHERE gm.group_id = '10000000-0000-4000-8000-000000000001'
ORDER BY gm.role, s.name;

-- Пример создания группы
-- INSERT INTO groups (group_id, name)
-- VALUES ('10000000-0000-4000-8000-000000000004', 'Новая группа');

-- Пример добавления существующего студента в существующую группу
-- INSERT INTO group_members (student_id, group_id, role)
-- VALUES (
--     '00000000-0000-4000-8000-000000000004',
--     '10000000-0000-4000-8000-000000000001',
--     'member'
-- );

-- Пример изменения роли участника
-- UPDATE group_members
-- SET role = 'admin'
-- WHERE student_id = '00000000-0000-4000-8000-000000000002'
--   AND group_id = '10000000-0000-4000-8000-000000000001';

-- ============================================================
-- 3. ПРИГЛАСИТЕЛЬНЫЕ ССЫЛКИ
-- ============================================================

-- Получить токен приглашения для конкретной группы
SELECT g.name AS group_name, il.token, il.created_at
FROM invite_links il
JOIN groups g ON g.group_id = il.group_id
WHERE g.group_id = '10000000-0000-4000-8000-000000000001';

-- Найти группу по токену приглашения
SELECT g.group_id, g.name AS group_name
FROM invite_links il
JOIN groups g ON g.group_id = il.group_id
WHERE il.token = '30000000-0000-4000-8000-000000000002';

-- Пример перевыпуска токена приглашения
-- UPDATE invite_links
-- SET token = '30000000-0000-4000-8000-000000000004',
--     created_at = NOW()
-- WHERE group_id = '10000000-0000-4000-8000-000000000001';

-- ============================================================
-- 4. ЛИЧНЫЕ И ГРУППОВЫЕ ЗАДАНИЯ
-- ============================================================

-- Личные задания, созданные конкретным студентом
SELECT task_id, title, description, due_at
FROM tasks
WHERE author_id = '00000000-0000-4000-8000-000000000001'
  AND kind = 'personal'
ORDER BY due_at;

-- Групповые задания с названием группы и автором
SELECT t.task_id, t.title, g.name AS group_name,
       s.name AS author_name, t.due_at
FROM tasks t
JOIN groups g ON g.group_id = t.group_id
JOIN students s ON s.student_id = t.author_id
WHERE t.kind = 'shared'
ORDER BY t.due_at;

-- Задания конкретной группы по сроку выполнения
SELECT task_id, title, description, due_at
FROM tasks
WHERE group_id = '10000000-0000-4000-8000-000000000001'
ORDER BY due_at;

-- Все просроченные задания
SELECT task_id, title, kind, due_at
FROM tasks
WHERE due_at < NOW()
ORDER BY due_at;

-- Пример создания личного задания
-- INSERT INTO tasks
--     (task_id, title, description, due_at, kind, author_id, group_id)
-- VALUES (
--     '20000000-0000-4000-8000-000000000008',
--     'Подготовить отчёт', 'Написать индивидуальный отчёт',
--     NOW() + INTERVAL '10 days', 'personal',
--     '00000000-0000-4000-8000-000000000001', NULL
-- );

-- Пример создания группового задания
-- INSERT INTO tasks
--     (task_id, title, description, due_at, kind, author_id, group_id)
-- VALUES (
--     '20000000-0000-4000-8000-000000000009',
--     'Подготовить презентацию', 'Общий доклад группы',
--     NOW() + INTERVAL '14 days', 'shared',
--     '00000000-0000-4000-8000-000000000001',
--     '10000000-0000-4000-8000-000000000001'
-- );

-- ============================================================
-- 5. СТАТУСЫ ВЫПОЛНЕНИЯ
-- ============================================================

-- Статусы всех студентов по конкретному заданию
SELECT s.name AS student_name, ts.status, ts.changed_at
FROM task_statuses ts
JOIN students s ON s.student_id = ts.student_id
WHERE ts.task_id = '20000000-0000-4000-8000-000000000001'
ORDER BY s.name;

-- Все задания студента, для которых задан статус
SELECT t.title, t.kind, t.due_at, ts.status, ts.changed_at
FROM task_statuses ts
JOIN tasks t ON t.task_id = ts.task_id
WHERE ts.student_id = '00000000-0000-4000-8000-000000000002'
ORDER BY t.due_at;

-- Пример создания индивидуального статуса
-- INSERT INTO task_statuses (student_id, task_id, status)
-- VALUES (
--     '00000000-0000-4000-8000-000000000003',
--     '20000000-0000-4000-8000-000000000002',
--     'not_started'
-- );

-- Пример изменения статуса с обновлением времени
-- UPDATE task_statuses
-- SET status = 'done', changed_at = NOW()
-- WHERE student_id = '00000000-0000-4000-8000-000000000001'
--   AND task_id = '20000000-0000-4000-8000-000000000001';

-- ============================================================
-- 6. СТАТИСТИКА И ОТЧЁТЫ
-- ============================================================

-- Количество участников в каждой группе
SELECT g.group_id, g.name AS group_name,
       COUNT(gm.student_id) AS members_count
FROM groups g
LEFT JOIN group_members gm ON gm.group_id = g.group_id
GROUP BY g.group_id, g.name
ORDER BY g.name;

-- Число личных и групповых заданий
SELECT kind, COUNT(*) AS tasks_count
FROM tasks
GROUP BY kind
ORDER BY kind;

-- Количество статусов по типам
SELECT status, COUNT(*) AS students_tasks_count
FROM task_statuses
GROUP BY status
ORDER BY status;

-- Статистика выполнения каждого задания (среди записанных статусов)
SELECT t.task_id, t.title,
       COUNT(ts.student_id) AS statuses_count,
       COUNT(*) FILTER (WHERE ts.status = 'done') AS done_count,
       COUNT(*) FILTER (WHERE ts.status = 'in_progress') AS in_progress_count,
       COUNT(*) FILTER (WHERE ts.status = 'not_started') AS not_started_count
FROM tasks t
LEFT JOIN task_statuses ts ON ts.task_id = t.task_id
GROUP BY t.task_id, t.title
ORDER BY t.title;

-- Число групп и групповых заданий у каждого студента
SELECT s.student_id, s.name,
       COUNT(DISTINCT gm.group_id) AS groups_count,
       COUNT(DISTINCT t.task_id) AS authored_shared_tasks_count
FROM students s
LEFT JOIN group_members gm ON gm.student_id = s.student_id
LEFT JOIN tasks t ON t.author_id = s.student_id AND t.kind = 'shared'
GROUP BY s.student_id, s.name
ORDER BY s.name;
