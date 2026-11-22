-- ============================================================
-- Основные запросы
-- Значения вида 'new@example.com' или 2 подставляются приложением
-- как параметры запроса (защита от SQL Injection, НФТ)
-- ============================================================


-- ============================================================
-- РЕГИСТРАЦИЯ И ВХОД
-- ============================================================

-- Проверка, что e-mail свободен
SELECT EXISTS (SELECT 1 FROM users WHERE email = 'new@example.com') AS email_taken;

-- Регистрация: пользователь + токен для письма (одной транзакцией)
BEGIN;
WITH new_user AS (
    INSERT INTO users (name, email, password_hash)
    VALUES ('Новый Студент', 'new@example.com', '$2b$12$hash_new')
    RETURNING user_id
)
INSERT INTO account_activation_tokens (token, user_id, expires_at)
SELECT 'a1b2c3d4e5f60718293a4b5c6d7e8f90', user_id, CURRENT_TIMESTAMP + INTERVAL '24 hours'
FROM new_user;
COMMIT;

-- Повторная отправка письма: новый токен вместо старого
BEGIN;
DELETE FROM account_activation_tokens
WHERE user_id = (SELECT user_id FROM users WHERE email = 'new@example.com');
INSERT INTO account_activation_tokens (token, user_id, expires_at)
SELECT '0f9e8d7c6b5a49382716a5b4c3d2e1f0', user_id, CURRENT_TIMESTAMP + INTERVAL '24 hours'
FROM users WHERE email = 'new@example.com';
COMMIT;

-- Переход по ссылке из письма: активация и удаление токена
BEGIN;
UPDATE users
SET status = 'active', updated_at = CURRENT_TIMESTAMP
WHERE user_id = (SELECT user_id FROM account_activation_tokens
                 WHERE token = '0f9e8d7c6b5a49382716a5b4c3d2e1f0'
                   AND expires_at > CURRENT_TIMESTAMP);
DELETE FROM account_activation_tokens WHERE token = '0f9e8d7c6b5a49382716a5b4c3d2e1f0';
COMMIT;

-- Вход: найти активного пользователя по e-mail (хеш пароля сверяет приложение)
SELECT user_id, name, password_hash
FROM users
WHERE email = 'maria@example.com' AND status = 'active';


-- ============================================================
-- ТЕОРЕТИЧЕСКИЕ МАТЕРИАЛЫ (доступны гостю и студенту)
-- ============================================================

-- Карточки методов на главной
SELECT a.code, a.name, a.task_type, t.title
FROM algorithms a
JOIN theory_materials t ON t.algorithm_id = a.algorithm_id AND t.section = 'method'
ORDER BY a.algorithm_id;

-- Страница метода
SELECT t.title, t.content, t.updated_at
FROM theory_materials t
JOIN algorithms a ON a.algorithm_id = t.algorithm_id
WHERE a.code = 'knn';

-- Справочник метрик (регрессия и классификация)
SELECT material_id, title, content
FROM theory_materials
WHERE section = 'metrics'
ORDER BY material_id;


-- ============================================================
-- ЭКСПЕРИМЕНТ
-- ============================================================

-- Ограничение нагрузки: сколько экспериментов студент запустил за последнюю минуту
-- (не более 5, НФТ)
SELECT COUNT(*) AS started_last_minute
FROM experiments
WHERE user_id = 2 AND started_at > CURRENT_TIMESTAMP - INTERVAL '1 minute';

-- Загрузка CSV (файл уже сохранён на диск)
INSERT INTO datasets (user_id, name, file_path, file_size)
VALUES (2, 'wine.csv', '/data/uploads/2/wine.csv', 10240)
RETURNING dataset_id;

-- Запуск обучения: запись эксперимента и гиперпараметры (одной транзакцией)
BEGIN;
WITH e AS (
    INSERT INTO experiments (user_id, dataset_id, algorithm_id, task_type,
                             target_column, feature_columns)
    VALUES (2, 3, (SELECT algorithm_id FROM algorithms WHERE code = 'random_forest'),
            'classification', 'survived', ARRAY['pclass', 'age'])
    RETURNING experiment_id
)
INSERT INTO experiment_settings (experiment_id, param_name, param_value)
SELECT e.experiment_id, p.name, p.value
FROM e, (VALUES ('n_estimators', '200'), ('max_depth', '8'), ('test_size', '0.2')) AS p(name, value);
COMMIT;

-- Обучение завершилось успешно: дополнить запись, сохранить метрики и модель
BEGIN;
UPDATE experiments
SET status = 'completed', finished_at = CURRENT_TIMESTAMP,
    plot_data = '{"type": "confusion_matrix", "labels": [0, 1], "matrix": [[95, 15], [20, 49]]}'
WHERE experiment_id = 5;
INSERT INTO experiment_metrics (experiment_id, metric_name, metric_value) VALUES
    (5, 'accuracy', 0.8045), (5, 'precision', 0.7656), (5, 'recall', 0.7101),
    (5, 'f1_score', 0.7368), (5, 'roc_auc', 0.8512);
INSERT INTO trained_models (experiment_id, file_path) VALUES (5, '/data/models/5.joblib');
COMMIT;

-- Обучение завершилось ошибкой
UPDATE experiments
SET status = 'failed', finished_at = CURRENT_TIMESTAMP,
    error_message = 'Столбец age содержит нечисловые значения'
WHERE experiment_id = 6;

-- Результаты обучения (страница результатов)
SELECT metric_name, metric_value
FROM experiment_metrics
WHERE experiment_id = 5
ORDER BY result_id;


-- ============================================================
-- ЛИЧНЫЙ КАБИНЕТ
-- ============================================================

-- Профиль: имя, e-mail, дата регистрации, число экспериментов
SELECT u.name, u.email, u.created_at::date AS registered,
       COUNT(e.experiment_id) AS experiments_count
FROM users u
LEFT JOIN experiments e ON e.user_id = u.user_id
WHERE u.user_id = 1
GROUP BY u.user_id;

-- Редактирование профиля
UPDATE users
SET name = 'Иван Петров-Водкин', email = 'ivan.p@example.com', updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1;

-- История экспериментов: дата, алгоритм, датасет, ключевая метрика, статус
-- (фильтры по алгоритму и статусу — необязательные параметры)
SELECT e.experiment_id,
       e.started_at,
       a.name  AS algorithm,
       d.name  AS dataset,
       m.metric_name,
       m.metric_value,
       e.status
FROM experiments e
JOIN algorithms a ON a.algorithm_id = e.algorithm_id
JOIN datasets  d ON d.dataset_id  = e.dataset_id
LEFT JOIN experiment_metrics m
       ON m.experiment_id = e.experiment_id
      AND m.metric_name = CASE e.task_type WHEN 'regression' THEN 'r2_score' ELSE 'accuracy' END
WHERE e.user_id = 1
  AND (NULL::text IS NULL OR a.code = NULL::text)        -- фильтр по алгоритму
  AND (NULL::text IS NULL OR e.status = NULL::text)      -- фильтр по статусу
ORDER BY e.started_at DESC;

-- Детали эксперимента: постановка задачи и доступна ли модель для скачивания
SELECT e.experiment_id, a.name AS algorithm, d.name AS dataset, e.task_type,
       e.target_column, e.feature_columns, e.status, e.started_at, e.finished_at,
       e.error_message, e.plot_data,
       (tm.model_id IS NOT NULL AND tm.expires_at > CURRENT_TIMESTAMP) AS model_available
FROM experiments e
JOIN algorithms a ON a.algorithm_id = e.algorithm_id
JOIN datasets  d ON d.dataset_id  = e.dataset_id
LEFT JOIN trained_models tm ON tm.experiment_id = e.experiment_id
WHERE e.experiment_id = 4 AND e.user_id = 2;

-- Детали эксперимента: гиперпараметры
SELECT param_name, param_value
FROM experiment_settings
WHERE experiment_id = 4
ORDER BY setting_id;

-- Детали эксперимента: метрики
SELECT metric_name, metric_value
FROM experiment_metrics
WHERE experiment_id = 4
ORDER BY result_id;

-- Скачать модель (только свою и только пока она хранится)
SELECT tm.file_path
FROM trained_models tm
JOIN experiments e ON e.experiment_id = tm.experiment_id
WHERE tm.experiment_id = 4 AND e.user_id = 2
  AND tm.expires_at > CURRENT_TIMESTAMP;

-- «Повторить с этими параметрами»: данные для заполнения страницы эксперимента
SELECT a.code AS algorithm, e.dataset_id, e.task_type, e.target_column, e.feature_columns,
       json_object_agg(s.param_name, s.param_value) AS hyperparameters
FROM experiments e
JOIN algorithms a ON a.algorithm_id = e.algorithm_id
LEFT JOIN experiment_settings s ON s.experiment_id = e.experiment_id
WHERE e.experiment_id = 2 AND e.user_id = 1
GROUP BY e.experiment_id, a.code;


-- ============================================================
-- СЛУЖЕБНЫЕ ЗАДАЧИ (запускаются по расписанию)
-- ============================================================

-- Удалить модели старше 30 дней (файлы удаляет приложение по возвращённым путям),
-- метрики экспериментов при этом остаются
DELETE FROM trained_models
WHERE expires_at <= CURRENT_TIMESTAMP
RETURNING experiment_id, file_path;

-- Таймаут обучения 5 минут: завершить «зависшие» эксперименты
UPDATE experiments
SET status = 'failed', finished_at = CURRENT_TIMESTAMP,
    error_message = 'Превышено время обучения (5 минут)'
WHERE status = 'running' AND started_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes'
RETURNING experiment_id;

-- Удалить просроченные токены активации
DELETE FROM account_activation_tokens
WHERE expires_at <= CURRENT_TIMESTAMP;
