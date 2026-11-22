-- ============================================================
-- Abstracteam: тестовое заполнение физической модели БД
-- СУБД: PostgreSQL
-- Заполняются все 11 таблиц согласно abstracteam_schema.sql.
-- Запускать на пустой БД после создания схемы.
-- Даты мероприятий вычисляются относительно CURRENT_DATE.
-- Пароли и токены ниже являются демонстрационными заглушками,
-- а не рабочими значениями для авторизации.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ПОЛЬЗОВАТЕЛИ
-- ============================================================

INSERT INTO users (full_name, email, password_hash, role, status) VALUES
    ('Павел Смирнов',  'admin@abstracteam.local',  'demo_hash_admin',   'admin',   'active'),
    ('Анна Смирнова',  'anna@abstracteam.local',   'demo_hash_anna',    'student', 'active'),
    ('Иван Петров',    'ivan@abstracteam.local',   'demo_hash_ivan',    'student', 'active'),
    ('Мария Соколова', 'maria@abstracteam.local',  'demo_hash_maria',   'student', 'active'),
    ('Дмитрий Кузнецов','dmitry@abstracteam.local','demo_hash_dmitry',  'student', 'active'),
    ('Елена Волкова',  'elena@abstracteam.local',  'demo_hash_elena',   'student', 'active'),
    ('Артём Морозов',  'artem@abstracteam.local',  'demo_hash_artem',   'student', 'active'),
    ('София Лебедева', 'sofia@abstracteam.local',  'demo_hash_sofia',   'student', 'active'),
    ('Никита Орлов',   'nikita@abstracteam.local', 'demo_hash_nikita',  'student', 'active'),
    ('Ольга Романова', 'olga@abstracteam.local',   'demo_hash_olga',    'student', 'inactive'),
    ('Борис Егоров',   'boris@abstracteam.local',  'demo_hash_boris',   'student', 'blocked');

-- ============================================================
-- 2. ПРОФИЛИ СТУДЕНТОВ
-- ============================================================

INSERT INTO student_profiles (user_id, about, telegram)
SELECT u.user_id, p.about, p.telegram
FROM (VALUES
    ('anna@abstracteam.local',   'Изучаю машинное обучение и разработку интеллектуальных систем.', '@anna_smirnova'),
    ('ivan@abstracteam.local',   'Frontend-разработчик. Интересуюсь интерфейсами и командными проектами.', '@ivan_petrov'),
    ('maria@abstracteam.local',  'Занимаюсь анализом данных и научными исследованиями.', '@maria_sokolova'),
    ('dmitry@abstracteam.local', 'Разрабатываю на Java и C++. Участвую в хакатонах.', '@dima_kuznetsov'),
    ('elena@abstracteam.local',  'Интересуюсь Data Science, ML и стартапами.', '@elena_volkova'),
    ('artem@abstracteam.local',  'Разработчик веб-приложений. Работаю с React и Docker.', '@artem_morozov'),
    ('sofia@abstracteam.local',  'Изучаю искусственный интеллект и пишу научные статьи.', '@sofia_lebedeva'),
    ('nikita@abstracteam.local', 'Интересуюсь информационной безопасностью и системным программированием.', '@nikita_orlov'),
    ('olga@abstracteam.local',   'Начинающий специалист, ищу команду для первого проекта.', '@olga_romanova'),
    ('boris@abstracteam.local',  'Студент технического направления.', '@boris_egorov')
) AS p(email, about, telegram)
JOIN users u ON LOWER(u.email) = LOWER(p.email);

-- ============================================================
-- 3. ТОКЕНЫ АКТИВАЦИИ
-- ============================================================

-- Для активного пользователя токен уже использован.
-- Для неактивного пользователя токен ожидает подтверждения.
INSERT INTO account_activation_tokens (user_id, token_hash, expires_at, used_at)
SELECT u.user_id, 'demo_token_hash_anna', CURRENT_TIMESTAMP + INTERVAL '24 hours', CURRENT_TIMESTAMP
FROM users u
WHERE u.email = 'anna@abstracteam.local';

INSERT INTO account_activation_tokens (user_id, token_hash, expires_at)
SELECT u.user_id, 'demo_token_hash_olga', CURRENT_TIMESTAMP + INTERVAL '24 hours'
FROM users u
WHERE u.email = 'olga@abstracteam.local';

-- ============================================================
-- 4. СПРАВОЧНИК ТЕГОВ
-- ============================================================

INSERT INTO tags (name, category) VALUES
    ('Прикладная информатика', 'specialty'),
    ('Программная инженерия', 'specialty'),
    ('Информатика и вычислительная техника', 'specialty'),
    ('Искусственный интеллект', 'study_direction'),
    ('Веб-разработка', 'study_direction'),
    ('Анализ данных', 'study_direction'),
    ('Информационная безопасность', 'study_direction'),
    ('Python', 'technology_stack'),
    ('JavaScript', 'technology_stack'),
    ('React', 'technology_stack'),
    ('PostgreSQL', 'technology_stack'),
    ('Java', 'technology_stack'),
    ('C++', 'technology_stack'),
    ('Docker', 'technology_stack'),
    ('Machine Learning', 'technology_stack'),
    ('Хакатоны', 'interest'),
    ('Научные статьи', 'interest'),
    ('Стартапы', 'interest'),
    ('Кейс-чемпионаты', 'interest'),
    ('Анализ данных', 'interest');

-- ============================================================
-- 5. ТЕГИ ПРОФИЛЕЙ ПОЛЬЗОВАТЕЛЕЙ
-- ============================================================

INSERT INTO user_tags (user_id, tag_id)
SELECT u.user_id, t.tag_id
FROM (VALUES
    ('anna@abstracteam.local',   'specialty',         'Прикладная информатика'),
    ('anna@abstracteam.local',   'study_direction',   'Искусственный интеллект'),
    ('anna@abstracteam.local',   'technology_stack',  'Python'),
    ('anna@abstracteam.local',   'technology_stack',  'PostgreSQL'),
    ('anna@abstracteam.local',   'technology_stack',  'Machine Learning'),
    ('anna@abstracteam.local',   'interest',          'Хакатоны'),
    ('anna@abstracteam.local',   'interest',          'Стартапы'),

    ('ivan@abstracteam.local',   'specialty',         'Программная инженерия'),
    ('ivan@abstracteam.local',   'study_direction',   'Веб-разработка'),
    ('ivan@abstracteam.local',   'technology_stack',  'JavaScript'),
    ('ivan@abstracteam.local',   'technology_stack',  'React'),
    ('ivan@abstracteam.local',   'technology_stack',  'Docker'),
    ('ivan@abstracteam.local',   'interest',          'Хакатоны'),

    ('maria@abstracteam.local',  'specialty',         'Прикладная информатика'),
    ('maria@abstracteam.local',  'study_direction',   'Анализ данных'),
    ('maria@abstracteam.local',  'technology_stack',  'Python'),
    ('maria@abstracteam.local',  'technology_stack',  'PostgreSQL'),
    ('maria@abstracteam.local',  'interest',          'Научные статьи'),
    ('maria@abstracteam.local',  'interest',          'Анализ данных'),

    ('dmitry@abstracteam.local','specialty',          'Программная инженерия'),
    ('dmitry@abstracteam.local','study_direction',    'Искусственный интеллект'),
    ('dmitry@abstracteam.local','technology_stack',   'Java'),
    ('dmitry@abstracteam.local','technology_stack',   'C++'),
    ('dmitry@abstracteam.local','interest',           'Хакатоны'),
    ('dmitry@abstracteam.local','interest',           'Кейс-чемпионаты'),

    ('elena@abstracteam.local', 'specialty',          'Прикладная информатика'),
    ('elena@abstracteam.local', 'study_direction',    'Анализ данных'),
    ('elena@abstracteam.local', 'technology_stack',   'Python'),
    ('elena@abstracteam.local', 'technology_stack',   'Machine Learning'),
    ('elena@abstracteam.local', 'interest',           'Стартапы'),
    ('elena@abstracteam.local', 'interest',           'Анализ данных'),

    ('artem@abstracteam.local', 'specialty',          'Программная инженерия'),
    ('artem@abstracteam.local', 'study_direction',    'Веб-разработка'),
    ('artem@abstracteam.local', 'technology_stack',   'JavaScript'),
    ('artem@abstracteam.local', 'technology_stack',   'React'),
    ('artem@abstracteam.local', 'technology_stack',   'Docker'),
    ('artem@abstracteam.local', 'interest',           'Кейс-чемпионаты'),

    ('sofia@abstracteam.local', 'specialty',          'Информатика и вычислительная техника'),
    ('sofia@abstracteam.local', 'study_direction',    'Искусственный интеллект'),
    ('sofia@abstracteam.local', 'technology_stack',   'Python'),
    ('sofia@abstracteam.local', 'technology_stack',   'Machine Learning'),
    ('sofia@abstracteam.local', 'interest',           'Научные статьи'),

    ('nikita@abstracteam.local','specialty',          'Прикладная информатика'),
    ('nikita@abstracteam.local','study_direction',    'Информационная безопасность'),
    ('nikita@abstracteam.local','technology_stack',   'C++'),
    ('nikita@abstracteam.local','technology_stack',   'Java'),
    ('nikita@abstracteam.local','interest',           'Хакатоны')
) AS seed(email, category, tag_name)
JOIN users u ON LOWER(u.email) = LOWER(seed.email)
JOIN tags t ON t.category = seed.category AND t.name = seed.tag_name;

-- ============================================================
-- 6. МЕРОПРИЯТИЯ
-- ============================================================

INSERT INTO events (
    name, event_type, topic, description,
    application_deadline, start_date, end_date,
    participation_conditions, source_url, status
) VALUES
    (
        'AI Hackathon 2026', 'hackathon', 'Искусственный интеллект и машинное обучение',
        'Командная разработка прототипов решений на основе искусственного интеллекта.',
        CURRENT_DATE + 7, CURRENT_DATE + 14, CURRENT_DATE + 16,
        'Студенческие команды от 2 до 5 человек.',
        'https://example.com/ai-hackathon', 'published'
    ),
    (
        'Студенческая научная конференция', 'conference', 'Наука и информационные технологии',
        'Конференция для представления исследовательских и прикладных проектов студентов.',
        CURRENT_DATE + 10, CURRENT_DATE + 20, CURRENT_DATE + 20,
        'Принимаются тезисы студентов и аспирантов.',
        'https://example.com/student-conference', 'published'
    ),
    (
        'Case Battle: цифровые решения', 'case_championship', 'Цифровая трансформация бизнеса',
        'Командам предстоит разработать решение практического бизнес-кейса.',
        CURRENT_DATE + 5, CURRENT_DATE + 12, CURRENT_DATE + 13,
        'Участие индивидуальное или в команде до 4 человек.',
        'https://example.com/case-battle', 'published'
    ),
    (
        'Data Science Weekend', 'hackathon', 'Аналитика данных',
        'Практический хакатон по анализу данных и построению моделей.',
        CURRENT_DATE + 18, CURRENT_DATE + 25, CURRENT_DATE + 27,
        'Базовые знания Python и статистики.',
        'https://example.com/data-science-weekend', 'published'
    ),
    (
        'ИТ-конференция 2025', 'conference', 'Информационные технологии',
        'Архивное мероприятие для проверки отображения прошедших событий.',
        CURRENT_DATE - 410, CURRENT_DATE - 400, CURRENT_DATE - 399,
        'Мероприятие завершено.',
        'https://example.com/it-conference-2025', 'archived'
    ),
    (
        'Вебинар о карьере в IT', 'other', 'Карьера и развитие',
        'Информационный вебинар о стажировках и карьерных траекториях.',
        CURRENT_DATE + 30, CURRENT_DATE + 35, CURRENT_DATE + 35,
        'Регистрация открыта после публикации.',
        'https://example.com/it-career-webinar', 'unpublished'
    );

-- ============================================================
-- 7. ЗАЯВКИ НА ПОИСК КОМАНДЫ
-- ============================================================

INSERT INTO applications (
    event_id, author_id, title, description,
    available_places, status
)
SELECT
    e.event_id,
    u.user_id,
    seed.title,
    seed.description,
    seed.available_places,
    seed.status
FROM (VALUES
    ('AI Hackathon 2026', 'anna@abstracteam.local',
     'Ищем ML-инженера в команду',
     'Разрабатываем интеллектуальный сервис. Нужен участник с опытом Python и ML.', 2, 'open'),
    ('AI Hackathon 2026', 'ivan@abstracteam.local',
     'Нужен frontend-разработчик',
     'Ищем разработчика интерфейса для демонстрации нашего AI-продукта.', 1, 'open'),
    ('Студенческая научная конференция', 'maria@abstracteam.local',
     'Ищем соавтора для научной статьи',
     'Нужен соавтор для исследования методов анализа данных.', 2, 'open'),
    ('Case Battle: цифровые решения', 'dmitry@abstracteam.local',
     'Собираем команду для Case Battle',
     'Ищем участников с навыками разработки и проектирования решений.', 3, 'open'),
    (NULL, 'elena@abstracteam.local',
     'Ищем единомышленников для ML-проекта',
     'Общая заявка: хотим создать учебный проект по машинному обучению.', 2, 'open'),
    ('Data Science Weekend', 'artem@abstracteam.local',
     'Ищем разработчика интерфейса',
     'Для проекта по визуализации данных нужен frontend-разработчик.', 1, 'open'),
    (NULL, 'sofia@abstracteam.local',
     'Набор в команду завершён',
     'Демонстрационная закрытая заявка с нулём свободных мест.', 0, 'open')
) AS seed(event_name, author_email, title, description, available_places, status)
JOIN users u ON LOWER(u.email) = LOWER(seed.author_email)
LEFT JOIN events e ON e.name = seed.event_name;

-- ============================================================
-- 8. ТЕГИ ЗАЯВОК
-- ============================================================

INSERT INTO application_tags (application_id, tag_id)
SELECT a.application_id, t.tag_id
FROM (VALUES
    ('Ищем ML-инженера в команду',       'technology_stack', 'Python'),
    ('Ищем ML-инженера в команду',       'technology_stack', 'Machine Learning'),
    ('Ищем ML-инженера в команду',       'technology_stack', 'PostgreSQL'),
    ('Нужен frontend-разработчик',       'technology_stack', 'JavaScript'),
    ('Нужен frontend-разработчик',       'technology_stack', 'React'),
    ('Ищем соавтора для научной статьи', 'interest',         'Научные статьи'),
    ('Ищем соавтора для научной статьи', 'study_direction',  'Анализ данных'),
    ('Собираем команду для Case Battle', 'technology_stack', 'Java'),
    ('Собираем команду для Case Battle', 'technology_stack', 'C++'),
    ('Собираем команду для Case Battle', 'interest',         'Кейс-чемпионаты'),
    ('Ищем единомышленников для ML-проекта', 'technology_stack', 'Python'),
    ('Ищем единомышленников для ML-проекта', 'technology_stack', 'Machine Learning'),
    ('Ищем разработчика интерфейса',    'technology_stack', 'React'),
    ('Ищем разработчика интерфейса',    'technology_stack', 'JavaScript'),
    ('Набор в команду завершён',        'interest',         'Хакатоны')
) AS seed(application_title, category, tag_name)
JOIN applications a ON a.title = seed.application_title
JOIN tags t ON t.category = seed.category AND t.name = seed.tag_name;

-- ============================================================
-- 9. ОТКЛИКИ НА ЗАЯВКИ
-- ============================================================

-- Пользователь не откликается на собственную заявку.
-- Все указанные заявки открыты, поэтому триггер проверки откликов пропускает записи.
INSERT INTO responses (application_id, user_id, message, status)
SELECT a.application_id, u.user_id, seed.message, seed.status
FROM (VALUES
    ('Ищем ML-инженера в команду', 'ivan@abstracteam.local',
     'Могу разработать интерфейс и интегрировать его с API.', 'pending'),
    ('Ищем ML-инженера в команду', 'sofia@abstracteam.local',
     'Есть опыт Python и машинного обучения, хотела бы присоединиться.', 'accepted'),
    ('Ищем ML-инженера в команду', 'nikita@abstracteam.local',
     'Интересен проект, могу помочь с технической частью.', 'pending'),

    ('Нужен frontend-разработчик', 'anna@abstracteam.local',
     'Могу помочь с интеграцией интерфейса и ML-модуля.', 'pending'),
    ('Нужен frontend-разработчик', 'artem@abstracteam.local',
     'Работаю с React, готов обсудить участие.', 'rejected'),

    ('Ищем соавтора для научной статьи', 'elena@abstracteam.local',
     'Занимаюсь анализом данных и могу помочь с исследованием.', 'pending'),
    ('Ищем соавтора для научной статьи', 'sofia@abstracteam.local',
     'Есть опыт подготовки научных публикаций.', 'accepted'),

    ('Собираем команду для Case Battle', 'anna@abstracteam.local',
     'Могу участвовать в разработке прототипа.', 'pending'),

    ('Ищем единомышленников для ML-проекта', 'maria@abstracteam.local',
     'Могу помочь с анализом данных и исследовательской частью.', 'pending'),
    ('Ищем единомышленников для ML-проекта', 'ivan@abstracteam.local',
     'Готов сделать веб-интерфейс проекта.', 'rejected'),

    ('Ищем разработчика интерфейса', 'nikita@abstracteam.local',
     'Есть опыт разработки, готов подключиться.', 'accepted')
) AS seed(application_title, responder_email, message, status)
JOIN applications a ON a.title = seed.application_title
JOIN users u ON LOWER(u.email) = LOWER(seed.responder_email);

-- ============================================================
-- 10. УВЕДОМЛЕНИЯ
-- ============================================================

INSERT INTO notifications (user_id, category, channel, title, body, read_at)
SELECT u.user_id, seed.category, seed.channel, seed.title, seed.body, seed.read_at
FROM (VALUES
    ('anna@abstracteam.local',   'response_activity', 'in_app', 'Новый отклик',
     'На вашу заявку «Ищем ML-инженера в команду» поступил отклик.', NULL::timestamptz),
    ('anna@abstracteam.local',   'response_activity', 'email',  'Отклик принят',
     'Один из откликов на вашу заявку был принят.', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('ivan@abstracteam.local',   'new_application',   'in_app', 'Новая заявка',
     'Опубликована новая заявка на поиск команды для AI Hackathon 2026.', NULL::timestamptz),
    ('maria@abstracteam.local',  'response_activity', 'in_app', 'Новый отклик',
     'На вашу заявку для научной конференции поступил отклик.', NULL::timestamptz),
    ('dmitry@abstracteam.local', 'response_activity', 'email',  'Отклик на заявку',
     'На вашу заявку «Собираем команду для Case Battle» поступил отклик.', CURRENT_TIMESTAMP - INTERVAL '2 hours'),
    ('elena@abstracteam.local',  'new_application',   'in_app', 'Новая заявка',
     'Появилась новая заявка, которая может быть вам интересна.', NULL::timestamptz),
    ('artem@abstracteam.local',  'event_changed',     'email',  'Изменение мероприятия',
     'Обновлена информация о мероприятии Data Science Weekend.', NULL::timestamptz),
    ('sofia@abstracteam.local',  'response_activity', 'in_app', 'Отклик принят',
     'Ваш отклик на заявку был принят автором.', CURRENT_TIMESTAMP - INTERVAL '3 hours'),
    ('nikita@abstracteam.local', 'new_application',   'in_app', 'Новая заявка',
     'Опубликована заявка, соответствующая вашим интересам.', NULL::timestamptz)
) AS seed(email, category, channel, title, body, read_at)
JOIN users u ON LOWER(u.email) = LOWER(seed.email);

-- ============================================================
-- 11. НАСТРОЙКИ УВЕДОМЛЕНИЙ
-- ============================================================

INSERT INTO notification_settings (user_id, channel, category, is_enabled)
SELECT u.user_id, seed.channel, seed.category, seed.is_enabled
FROM (VALUES
    ('anna@abstracteam.local',   'email',  'all',                TRUE),
    ('anna@abstracteam.local',   'email',  'new_application',    TRUE),
    ('anna@abstracteam.local',   'email',  'response_activity',  TRUE),
    ('anna@abstracteam.local',   'email',  'event_changed',      FALSE),
    ('anna@abstracteam.local',   'in_app', 'new_application',    TRUE),
    ('anna@abstracteam.local',   'in_app', 'response_activity',  TRUE),
    ('anna@abstracteam.local',   'in_app', 'event_changed',      TRUE),

    ('ivan@abstracteam.local',   'email',  'all',                TRUE),
    ('ivan@abstracteam.local',   'in_app', 'new_application',    TRUE),
    ('ivan@abstracteam.local',   'in_app', 'response_activity',  TRUE),
    ('ivan@abstracteam.local',   'in_app', 'event_changed',      FALSE),

    ('maria@abstracteam.local',  'email',  'all',                FALSE),
    ('maria@abstracteam.local',  'in_app', 'new_application',    TRUE),
    ('maria@abstracteam.local',  'in_app', 'response_activity',  TRUE),
    ('maria@abstracteam.local',  'in_app', 'event_changed',      TRUE),

    ('elena@abstracteam.local',  'email',  'all',                TRUE),
    ('elena@abstracteam.local',  'in_app', 'new_application',    TRUE),
    ('elena@abstracteam.local',  'in_app', 'response_activity',  TRUE),
    ('elena@abstracteam.local',  'in_app', 'event_changed',      TRUE)
) AS seed(email, channel, category, is_enabled)
JOIN users u ON LOWER(u.email) = LOWER(seed.email);

-- ============================================================
-- ПРОВЕРКА ЗАПОЛНЕНИЯ ВСЕХ 11 ТАБЛИЦ
-- ============================================================

SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'student_profiles', COUNT(*) FROM student_profiles
UNION ALL SELECT 'account_activation_tokens', COUNT(*) FROM account_activation_tokens
UNION ALL SELECT 'tags', COUNT(*) FROM tags
UNION ALL SELECT 'user_tags', COUNT(*) FROM user_tags
UNION ALL SELECT 'events', COUNT(*) FROM events
UNION ALL SELECT 'applications', COUNT(*) FROM applications
UNION ALL SELECT 'application_tags', COUNT(*) FROM application_tags
UNION ALL SELECT 'responses', COUNT(*) FROM responses
UNION ALL SELECT 'notifications', COUNT(*) FROM notifications
UNION ALL SELECT 'notification_settings', COUNT(*) FROM notification_settings
ORDER BY table_name;

COMMIT;
