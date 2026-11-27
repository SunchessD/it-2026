-- ============================================================
-- Тестовые данные
-- Порядок вставки учитывает внешние ключи
-- ============================================================

-- 1. ПОЛЬЗОВАТЕЛИ (пароли — условные хеши)
INSERT INTO users (name, email, password_hash, status, created_at) VALUES
    ('Иван Петров',    'ivan@example.com',   '$2b$12$hash_ivan',   'active',   '2026-10-01 10:00'),
    ('Мария Сидорова', 'maria@example.com',  '$2b$12$hash_maria',  'active',   '2026-10-05 14:30'),
    ('Алексей Козлов', 'alexey@example.com', '$2b$12$hash_alexey', 'inactive', '2026-11-12 09:15');

-- 2. ТОКЕНЫ АКТИВАЦИИ (Алексей ещё не перешёл по ссылке из письма)
INSERT INTO account_activation_tokens (token, user_id, expires_at) VALUES
    ('f3a9c1e07b2d4e6f8a0b1c2d3e4f5a6b', 3, '2026-11-13 09:15');

-- 3. АЛГОРИТМЫ
INSERT INTO algorithms (code, name, task_type) VALUES
    ('linear_regression',   'Линейная регрессия',             'regression'),
    ('logistic_regression', 'Логистическая регрессия',        'classification'),
    ('random_forest',       'Случайный лес',                  'both'),
    ('knn',                 'Метод k-ближайших соседей (kNN)', 'both');

-- 4. ТЕОРЕТИЧЕСКИЕ МАТЕРИАЛЫ (4 страницы методов + 2 страницы справочника метрик)
INSERT INTO theory_materials (section, algorithm_id, title, content) VALUES
    ('method',  1,    'Линейная регрессия',      'Предсказывает число как линейную комбинацию признаков...'),
    ('method',  2,    'Логистическая регрессия', 'Оценивает вероятность принадлежности к классу...'),
    ('method',  3,    'Случайный лес',           'Ансамбль решающих деревьев...'),
    ('method',  4,    'Метод k-ближайших соседей', 'Предсказание по k ближайшим объектам обучающей выборки...'),
    ('metrics', NULL, 'Метрики регрессии',       'MAE, MSE, RMSE, R²...'),
    ('metrics', NULL, 'Метрики классификации',   'Accuracy, Precision, Recall, F1, ROC-AUC...');

-- 5. НАБОРЫ ДАННЫХ
INSERT INTO datasets (user_id, name, description, file_path, file_size, uploaded_at) VALUES
    (1, 'house_prices.csv', 'Цены на квартиры', '/data/uploads/1/house_prices.csv', 2457600, '2026-10-02 11:00'),
    (1, 'iris.csv',         NULL,               '/data/uploads/1/iris.csv',            4608, '2026-11-10 18:20'),
    (2, 'titanic.csv',      'Выжившие на Титанике', '/data/uploads/2/titanic.csv',    61194, '2026-10-06 16:00');

-- 6. ЭКСПЕРИМЕНТЫ
INSERT INTO experiments (user_id, dataset_id, algorithm_id, task_type, target_column, feature_columns,
                         status, started_at, finished_at, error_message, plot_data) VALUES
    -- 1: Иван, линейная регрессия — успешно
    (1, 1, 1, 'regression', 'price', ARRAY['area', 'rooms', 'floor'],
     'completed', '2026-10-02 11:05:00', '2026-10-02 11:05:03', NULL,
     '{"type": "scatter", "y_true": [5.1, 6.3], "y_pred": [5.0, 6.6]}'),
    -- 2: Иван, kNN на том же файле — успешно (модель уже удалена через 30 дней)
    (1, 1, 4, 'regression', 'price', ARRAY['area', 'rooms'],
     'completed', '2026-10-02 11:10:00', '2026-10-02 11:10:12', NULL, NULL),
    -- 3: Иван, случайный лес — ошибка обучения
    (1, 2, 3, 'classification', 'species', ARRAY['sepal_length', 'sepal_width'],
     'failed', '2026-11-10 18:25:00', '2026-11-10 18:25:02', 'Целевая переменная содержит пропуски', NULL),
    -- 4: Мария, логистическая регрессия — успешно
    (2, 3, 2, 'classification', 'survived', ARRAY['pclass', 'age', 'fare'],
     'completed', '2026-11-11 16:05:00', '2026-11-11 16:05:02', NULL,
     '{"type": "confusion_matrix", "labels": [0, 1], "matrix": [[98, 12], [17, 52]]}'),
    -- 5: Мария, kNN — ещё обучается
    (2, 3, 4, 'classification', 'survived', ARRAY['pclass', 'age', 'fare', 'sex'],
     'running', '2026-11-13 12:00:00', NULL, NULL, NULL);

-- 7. НАСТРОЙКИ (гиперпараметры)
INSERT INTO experiment_settings (experiment_id, param_name, param_value) VALUES
    (1, 'alpha', '1.0'), (1, 'fit_intercept', 'true'), (1, 'test_size', '0.2'),
    (2, 'n_neighbors', '5'), (2, 'weights', 'distance'), (2, 'metric', 'minkowski'), (2, 'p', '2'), (2, 'test_size', '0.2'),
    (3, 'n_estimators', '100'), (3, 'max_depth', '10'), (3, 'test_size', '0.3'),
    (4, 'C', '1.0'), (4, 'penalty', 'l2'), (4, 'max_iter', '1000'), (4, 'test_size', '0.2'),
    (5, 'n_neighbors', '7'), (5, 'weights', 'uniform'), (5, 'test_size', '0.25');

-- 8. РЕЗУЛЬТАТЫ (метрики качества)
INSERT INTO experiment_metrics (experiment_id, metric_name, metric_value) VALUES
    (1, 'mae', 0.4120), (1, 'mse', 0.3011), (1, 'rmse', 0.5487), (1, 'r2_score', 0.8215),
    (2, 'mae', 0.3804), (2, 'mse', 0.2650), (2, 'rmse', 0.5148), (2, 'r2_score', 0.8431),
    (4, 'accuracy', 0.8380), (4, 'precision', 0.8125), (4, 'recall', 0.7536),
    (4, 'f1_score', 0.7820), (4, 'roc_auc', 0.8794);

-- 9. ОБУЧЕННЫЕ МОДЕЛИ (у эксперимента 2 модель уже удалена, у 3 и 5 её нет)
INSERT INTO trained_models (experiment_id, file_path, created_at) VALUES
    (1, '/data/models/1.joblib', '2026-10-02 11:05:03'),
    (4, '/data/models/4.joblib', '2026-11-11 16:05:02');
