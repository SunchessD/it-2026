-- ============================================================
-- Веб-приложение для организации онлайн-обучения и тестирования
-- Команда № 10
-- Основные SQL-запросы для реализации вариантов использования
-- ============================================================

-- ------------------------------------------------------------
-- 1. АУТЕНТИФИКАЦИЯ И РЕГИСТРАЦИЯ (ВИ-1.1, ВИ-1.2)
-- ------------------------------------------------------------

-- Проверка доступности email при регистрации
SELECT COUNT(*) = 0 AS is_available
FROM users
WHERE lower(email) = lower(:email);

-- Поиск пользователя по email для аутентификации
SELECT id, name, email, password_hash, role, status
FROM users
WHERE lower(email) = lower(:email);

-- Активация учетной записи по токену подтверждения
UPDATE users
SET status = 'active', updated_at = now()
WHERE id = (
    SELECT user_id
    FROM email_activation_tokens
    WHERE token_hash = :token_hash
      AND expires_at > now()
      AND used_at IS NULL
);

-- Пометка токена активации как использованного
UPDATE email_activation_tokens
SET used_at = now()
WHERE token_hash = :token_hash;

-- ------------------------------------------------------------
-- 2. КАТАЛОГ КУРСОВ И КАРТОЧКА ОПИСАНИЯ (ВИ-2.1, ВИ-2.2)
-- ------------------------------------------------------------

-- Выборка опубликованных курсов с фильтрацией по категории и пагинацией
SELECT c.id, c.title, c.difficulty, cat.name AS category_name, u.name AS author_name,
       COUNT(DISTINCT l.id) AS total_lessons,
       COUNT(DISTINCT t.id) AS total_tests
FROM courses c
JOIN categories cat ON cat.id = c.category_id
JOIN users u ON u.id = c.author_id
LEFT JOIN modules m ON m.course_id = c.id
LEFT JOIN lessons l ON l.module_id = m.id
LEFT JOIN tests t ON t.module_id = m.id
WHERE c.status = 'published'
  AND (:category_id IS NULL OR c.category_id = :category_id)
  AND (:difficulty IS NULL OR c.difficulty = :difficulty)
  AND (:search_text IS NULL OR c.title ILIKE '%' || :search_text || '%')
GROUP BY c.id, c.title, c.difficulty, cat.name, u.name, c.created_at
ORDER BY c.created_at DESC
LIMIT 12 OFFSET :offset;

-- Детальная карточка курса для неавторизованного пользователя
SELECT c.id, c.title, c.description, c.difficulty,
       cat.name AS category_name, u.name AS author_name,
       c.created_at
FROM courses c
JOIN categories cat ON cat.id = c.category_id
JOIN users u ON u.id = c.author_id
WHERE c.id = :course_id AND c.status = 'published';

-- ------------------------------------------------------------
-- 3. ПРОГРАММА КУРСА И ОБУЧЕНИЕ (ВИ-2.3, ВИ-3.1, ВИ-3.2)
-- ------------------------------------------------------------

-- Проверка и создание записи студента на курс
INSERT INTO enrollments (student_id, course_id, progress_percent, status)
SELECT :student_id, :course_id, 0, 'active'
WHERE EXISTS (
    SELECT 1 FROM courses WHERE id = :course_id AND status = 'published'
)
ON CONFLICT (student_id, course_id) DO NOTHING
RETURNING id, progress_percent, status;

-- Получение программы курса со статусом прохождения уроков студентом
SELECT m.id AS module_id, m.position AS module_pos, m.title AS module_title,
       l.id AS lesson_id, l.position AS lesson_pos, l.title AS lesson_title,
       CASE WHEN lc.id IS NOT NULL THEN true ELSE false END AS is_completed
FROM modules m
LEFT JOIN lessons l ON l.module_id = m.id
LEFT JOIN lesson_completions lc ON lc.lesson_id = l.id AND lc.enrollment_id = :enrollment_id
WHERE m.course_id = :course_id
ORDER BY m.position, l.position;

-- Отметка о завершении урока
INSERT INTO lesson_completions (enrollment_id, lesson_id)
VALUES (:enrollment_id, :lesson_id)
ON CONFLICT (enrollment_id, lesson_id) DO NOTHING;

-- Пересчет суммарного прогресса зачисления (доля пройденных занятий и сданных тестов)
WITH course_stats AS (
    SELECT
        COUNT(DISTINCT l.id) AS total_lessons,
        COUNT(DISTINCT t.id) AS total_tests
    FROM enrollments e
    JOIN courses c ON c.id = e.course_id
    LEFT JOIN modules m ON m.course_id = c.id
    LEFT JOIN lessons l ON l.module_id = m.id
    LEFT JOIN tests t ON t.module_id = m.id
    WHERE e.id = :enrollment_id
),
student_stats AS (
    SELECT
        COUNT(DISTINCT lc.lesson_id) AS done_lessons,
        COUNT(DISTINCT ta.test_id) AS passed_tests
    FROM enrollments e
    LEFT JOIN lesson_completions lc ON lc.enrollment_id = e.id
    LEFT JOIN test_attempts ta ON ta.enrollment_id = e.id AND ta.status = 'passed'
    WHERE e.id = :enrollment_id
)
UPDATE enrollments
SET progress_percent = LEAST(100, ROUND(
    (student_stats.done_lessons + student_stats.passed_tests)::numeric /
    NULLIF(course_stats.total_lessons + course_stats.total_tests, 0) * 100
)::smallint)
FROM course_stats, student_stats
WHERE enrollments.id = :enrollment_id
RETURNING enrollments.progress_percent, enrollments.status;

-- ------------------------------------------------------------
-- 4. ТЕСТИРОВАНИЕ И РАСЧЕТ БАЛЛОВ (ВИ-3.3)
-- ------------------------------------------------------------

-- Инициализация новой попытки тестирования
INSERT INTO test_attempts (enrollment_id, test_id, status, started_at)
VALUES (:enrollment_id, :test_id, 'in_progress', now())
RETURNING id, started_at;

-- Проверка и автоматический расчет процента за тест
WITH answers_score AS (
    -- Подсчет корректности ответов студента
    SELECT
        q.id AS question_id,
        q.points,
        CASE
            -- Для одиночного выбора: выбран ровно один правильный ответ
            WHEN q.question_type = 'single' THEN
                BOOL_AND(ao.is_correct) AND COUNT(aao.option_id) = 1
            -- Для множественного выбора: выбраны все верные и ни одного неверного
            WHEN q.question_type = 'multiple' THEN
                (SELECT COUNT(*) FROM answer_options WHERE question_id = q.id AND is_correct = true) =
                COUNT(CASE WHEN ao.is_correct = true THEN 1 END)
                AND COUNT(CASE WHEN ao.is_correct = false THEN 1 END) = 0
            ELSE false
        END AS is_question_correct
    FROM attempt_answers aa
    JOIN questions q ON q.id = aa.question_id
    LEFT JOIN attempt_answer_options aao ON aao.attempt_answer_id = aa.id
    LEFT JOIN answer_options ao ON ao.id = aao.option_id
    WHERE aa.attempt_id = :attempt_id
    GROUP BY q.id, q.points, q.question_type
),
totals AS (
    SELECT
        COALESCE(SUM(CASE WHEN is_question_correct THEN points ELSE 0 END), 0) AS earned_points,
        COALESCE(SUM(points), 1) AS max_points
    FROM answers_score
)
UPDATE test_attempts
SET
    score_percent = ROUND((totals.earned_points::numeric / totals.max_points) * 100)::smallint,
    status = CASE
        WHEN ROUND((totals.earned_points::numeric / totals.max_points) * 100) >= (SELECT passing_score_percent FROM tests WHERE id = test_attempts.test_id)
        THEN 'passed'
        ELSE 'failed'
    END,
    finished_at = now()
FROM totals
WHERE test_attempts.id = :attempt_id
RETURNING test_attempts.score_percent, test_attempts.status;

-- ------------------------------------------------------------
-- 5. СЕРТИФИКАЦИЯ (ВИ-3.4)
-- ------------------------------------------------------------

-- Генерация сертификата при достижении 100% прогресса
INSERT INTO certificates (enrollment_id, certificate_number, issued_at)
SELECT e.id, 'СЕРТ-' || to_char(now(), 'YYYY-MM-') || lpad(floor(random() * 90000 + 10000)::text, 5, '0'), now()
FROM enrollments e
WHERE e.id = :enrollment_id
  AND e.progress_percent = 100
  AND NOT EXISTS (SELECT 1 FROM certificates WHERE enrollment_id = e.id)
RETURNING id, certificate_number, issued_at;

-- ------------------------------------------------------------
-- 6. ПРЕПОДАВАТЕЛЬСКИЙ ИНТЕРФЕЙС И ВЕДОМОСТЬ (ВИ-4.1, ВИ-4.4)
-- ------------------------------------------------------------

-- Ведомость успеваемости студентов курса
SELECT u.name AS student_name, u.email AS student_email,
       e.progress_percent, e.status AS enrollment_status, e.enrolled_at,
       cert.certificate_number,
       AVG(ta.score_percent) AS avg_test_score
FROM enrollments e
JOIN users u ON u.id = e.student_id
LEFT JOIN certificates cert ON cert.enrollment_id = e.id
LEFT JOIN test_attempts ta ON ta.enrollment_id = e.id AND ta.status = 'passed'
WHERE e.course_id = :course_id
GROUP BY u.name, u.email, e.progress_percent, e.status, e.enrolled_at, cert.certificate_number
ORDER BY e.progress_percent DESC, u.name ASC;

-- ------------------------------------------------------------
-- 7. МОДЕРАЦИЯ КУРСОВ АДМИНИСТРАТОРОМ (ВИ-5.1)
-- ------------------------------------------------------------

-- Очередь курсов, ожидающих проверки модератором
SELECT c.id, c.title, c.difficulty, cat.name AS category_name,
       u.name AS author_name, u.email AS author_email,
       c.updated_at AS submitted_at,
       COUNT(DISTINCT m.id) AS modules_count,
       COUNT(DISTINCT l.id) AS lessons_count,
       COUNT(DISTINCT t.id) AS tests_count
FROM courses c
JOIN categories cat ON cat.id = c.category_id
JOIN users u ON u.id = c.author_id
LEFT JOIN modules m ON m.course_id = c.id
LEFT JOIN lessons l ON l.module_id = m.id
LEFT JOIN tests t ON t.module_id = m.id
WHERE c.status = 'pending'
GROUP BY c.id, c.title, c.difficulty, cat.name, u.name, u.email, c.updated_at
ORDER BY c.updated_at ASC;

-- Одобрение публикации курса
UPDATE courses
SET status = 'published', updated_at = now()
WHERE id = :course_id AND status = 'pending';

-- Отклонение публикации курса с сохранением замечаний
INSERT INTO moderation_decisions (course_id, admin_id, decision, comment, decided_at)
VALUES (:course_id, :admin_id, 'rejected', :comment, now());

UPDATE courses
SET status = 'draft', updated_at = now()
WHERE id = :course_id AND status = 'pending';
