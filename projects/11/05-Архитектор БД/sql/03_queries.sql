-- ============================================================
-- Веб-приложение "Мой список покупок"
-- Основные SQL-запросы (PostgreSQL)
-- ============================================================
-- Запросы на изменение данных предназначены для демонстрации.
-- При повторном выполнении измените уникальные значения.

-- ============================================================
-- 1. РЕГИСТРАЦИЯ, АВТОРИЗАЦИЯ И АКТИВАЦИЯ
-- ============================================================

-- 1.1. Регистрация нового пользователя
INSERT INTO users (name, email, password_hash, role, status)
VALUES ('Елена Смирнова', 'elena@example.com', 'secure_bcrypt_hash', 'user', 'inactive')
RETURNING user_id, email, status;

-- 1.2. Поиск активного пользователя при входе.
-- Пароль проверяется в приложении по password_hash через bcrypt/Argon2.
SELECT user_id, name, email, password_hash, role, status
FROM users
WHERE email = 'ivan@example.com' AND status = 'active';

-- 1.3. Активация учетной записи по одноразовому токену
WITH token_owner AS (
    DELETE FROM account_activation_tokens
    WHERE token = 'demo-activation-token'
      AND expires_at > CURRENT_TIMESTAMP
    RETURNING user_id
)
UPDATE users u
SET status = 'active'
FROM token_owner t
WHERE u.user_id = t.user_id
RETURNING u.user_id, u.email, u.status;

-- 1.4. Создание токена активации для нового пользователя.
-- Значение токена в реальном приложении формируется криптографически стойким генератором.
INSERT INTO account_activation_tokens (token, user_id, expires_at)
SELECT 'replace-with-secure-random-token', user_id, CURRENT_TIMESTAMP + INTERVAL '1 day'
FROM users
WHERE email = 'elena@example.com';

-- ============================================================
-- 2. УПРАВЛЕНИЕ СПИСКАМИ ПОКУПОК
-- ============================================================

-- 2.1. Создание нового списка
INSERT INTO shopping_lists (user_id, name, description)
VALUES (2, 'Покупки на выходные', 'Список для субботней закупки')
RETURNING list_id, name, created_at;

-- 2.2. Все списки пользователя с прогрессом покупок
SELECT
    sl.list_id,
    sl.name,
    sl.description,
    COUNT(i.item_id) AS total_items,
    COUNT(i.item_id) FILTER (WHERE i.is_purchased) AS purchased_items,
    COUNT(i.item_id) FILTER (WHERE NOT i.is_purchased) AS remaining_items,
    sl.updated_at
FROM shopping_lists sl
LEFT JOIN items i ON i.list_id = sl.list_id
WHERE sl.user_id = 2
GROUP BY sl.list_id, sl.name, sl.description, sl.updated_at
ORDER BY sl.updated_at DESC;

-- 2.3. Переименование списка
UPDATE shopping_lists
SET name = 'Продукты на текущую неделю'
WHERE list_id = 1 AND user_id = 2
RETURNING list_id, name, updated_at;

-- 2.4. Удаление списка; товары удаляются каскадно
DELETE FROM shopping_lists
WHERE list_id = 2 AND user_id = 2
RETURNING list_id, name;

-- ============================================================
-- 3. ТОВАРЫ, ПОИСК И ФИЛЬТРАЦИЯ
-- ============================================================

-- 3.1. Добавление товара в список
INSERT INTO items (list_id, category_id, name, quantity, unit)
VALUES (1, 6, 'Апельсиновый сок', 1.00, 'л')
RETURNING item_id, name, quantity, unit, is_purchased;

-- 3.2. Все товары списка: сначала неприобретенные
SELECT
    i.item_id,
    i.name,
    i.quantity,
    i.unit,
    c.name AS category,
    i.is_purchased,
    i.created_at,
    i.purchased_at
FROM items i
LEFT JOIN categories c ON c.category_id = i.category_id
WHERE i.list_id = 1
ORDER BY i.is_purchased, i.created_at DESC, i.name;

-- 3.3. Поиск товара по названию во всех списках пользователя
SELECT
    i.item_id,
    i.name AS item_name,
    sl.name AS list_name,
    i.quantity,
    i.unit,
    i.is_purchased
FROM items i
JOIN shopping_lists sl ON sl.list_id = i.list_id
WHERE sl.user_id = 2
  AND i.name ILIKE '%молоко%'
ORDER BY i.name;

-- 3.4. Фильтрация списка по категории
SELECT i.item_id, i.name, i.quantity, i.unit, i.is_purchased
FROM items i
WHERE i.list_id = 1
  AND i.category_id = 3
ORDER BY i.is_purchased, i.name;

-- 3.5. Отметить товар как приобретенный
UPDATE items
SET is_purchased = TRUE,
    purchased_at = CURRENT_TIMESTAMP
WHERE item_id = 1
RETURNING item_id, name, is_purchased, purchased_at;

-- 3.6. Отменить отметку о покупке
UPDATE items
SET is_purchased = FALSE,
    purchased_at = NULL
WHERE item_id = 3
RETURNING item_id, name, is_purchased, purchased_at;

-- 3.7. Изменить количество и единицу измерения
UPDATE items
SET quantity = 3.00,
    unit = 'л'
WHERE item_id = 1
RETURNING item_id, name, quantity, unit;

-- 3.8. Удалить товар из списка
DELETE FROM items
WHERE item_id = 7
RETURNING item_id, name;

-- ============================================================
-- 4. КАТЕГОРИИ
-- ============================================================

-- 4.1. Получить все категории
SELECT category_id, name, description
FROM categories
ORDER BY name;

-- 4.2. Добавить новую категорию
INSERT INTO categories (name, description)
VALUES ('Замороженные продукты', 'Овощи, полуфабрикаты и мороженое')
RETURNING category_id, name;

-- ============================================================
-- 5. СТАТИСТИКА И ОТЧЕТЫ
-- ============================================================

-- 5.1. Общая статистика пользователя
SELECT
    u.user_id,
    u.name,
    COUNT(DISTINCT sl.list_id) AS lists_count,
    COUNT(i.item_id) AS items_count,
    COUNT(i.item_id) FILTER (WHERE i.is_purchased) AS purchased_count,
    COUNT(i.item_id) FILTER (WHERE NOT i.is_purchased) AS remaining_count
FROM users u
LEFT JOIN shopping_lists sl ON sl.user_id = u.user_id
LEFT JOIN items i ON i.list_id = sl.list_id
WHERE u.user_id = 2
GROUP BY u.user_id, u.name;

-- 5.2. Распределение неприобретенных товаров по категориям
SELECT
    c.name AS category,
    COUNT(i.item_id) AS remaining_items
FROM categories c
LEFT JOIN items i
    ON i.category_id = c.category_id AND NOT i.is_purchased
LEFT JOIN shopping_lists sl ON sl.list_id = i.list_id
WHERE sl.user_id = 2 OR sl.user_id IS NULL
GROUP BY c.category_id, c.name
HAVING COUNT(i.item_id) > 0
ORDER BY remaining_items DESC, c.name;

-- 5.3. Списки, в которых все товары приобретены
SELECT sl.list_id, sl.name
FROM shopping_lists sl
JOIN items i ON i.list_id = sl.list_id
WHERE sl.user_id = 2
GROUP BY sl.list_id, sl.name
HAVING COUNT(*) = COUNT(*) FILTER (WHERE i.is_purchased)
ORDER BY sl.name;

-- 5.4. Статистика администратора по пользователям
SELECT
    u.user_id,
    u.name,
    u.email,
    u.status,
    COUNT(DISTINCT sl.list_id) AS lists_count,
    COUNT(i.item_id) AS items_count,
    u.created_at
FROM users u
LEFT JOIN shopping_lists sl ON sl.user_id = u.user_id
LEFT JOIN items i ON i.list_id = sl.list_id
GROUP BY u.user_id, u.name, u.email, u.status, u.created_at
ORDER BY u.created_at;
