-- ============================================================
-- Веб-приложение "Мой список покупок"
-- Тестовые данные (PostgreSQL)
-- ============================================================
-- Выполнять после 01_create_database.sql.
-- Хеши паролей являются учебными заполнителями. В приложении
-- необходимо использовать bcrypt или Argon2.

BEGIN;

-- 1. ПОЛЬЗОВАТЕЛИ
INSERT INTO users (user_id, name, email, password_hash, role, status) VALUES
    (1, 'Администратор', 'admin@example.com', 'demo_bcrypt_hash_admin', 'admin', 'active'),
    (2, 'Иван Петров', 'ivan@example.com', 'demo_bcrypt_hash_ivan', 'user', 'active'),
    (3, 'Мария Сидорова', 'maria@example.com', 'demo_bcrypt_hash_maria', 'user', 'active'),
    (4, 'Новый Пользователь', 'new@example.com', 'demo_bcrypt_hash_new', 'user', 'inactive');

-- 2. ТОКЕН АКТИВАЦИИ
INSERT INTO account_activation_tokens (token, user_id, expires_at) VALUES
    ('demo-activation-token', 4, CURRENT_TIMESTAMP + INTERVAL '1 day');

-- 3. КАТЕГОРИИ ТОВАРОВ
INSERT INTO categories (category_id, name, description) VALUES
    (1, 'Овощи', 'Свежие овощи и зелень'),
    (2, 'Фрукты', 'Фрукты и ягоды'),
    (3, 'Молочные продукты', 'Молоко, сыр, йогурт и другие продукты'),
    (4, 'Мясо и рыба', 'Мясные и рыбные продукты'),
    (5, 'Бакалея', 'Крупы, макароны, хлеб и консервы'),
    (6, 'Напитки', 'Вода, соки, чай и кофе'),
    (7, 'Бытовая химия', 'Товары для уборки и ухода за домом');

-- 4. СПИСКИ ПОКУПОК
INSERT INTO shopping_lists (list_id, user_id, name, description) VALUES
    (1, 2, 'Продукты на неделю', 'Основная закупка продуктов'),
    (2, 2, 'Дачная закупка', 'Продукты для поездки на дачу'),
    (3, 3, 'Дом и быт', 'Товары для дома'),
    (4, 3, 'Завтраки', 'Продукты для завтраков на неделю');

-- 5. ТОВАРЫ
INSERT INTO items
    (item_id, list_id, category_id, name, quantity, unit, is_purchased, purchased_at)
VALUES
    (1, 1, 3, 'Молоко', 2.00, 'л', FALSE, NULL),
    (2, 1, 2, 'Яблоки', 1.50, 'кг', FALSE, NULL),
    (3, 1, 1, 'Картофель', 2.00, 'кг', TRUE, CURRENT_TIMESTAMP - INTERVAL '2 hours'),
    (4, 1, 4, 'Куриное филе', 1.00, 'кг', FALSE, NULL),
    (5, 1, 3, 'Сыр', 0.50, 'кг', FALSE, NULL),
    (6, 1, 5, 'Гречка', 1.00, 'уп.', TRUE, CURRENT_TIMESTAMP - INTERVAL '1 day'),
    (7, 1, 6, 'Питьевая вода', 2.00, 'бут.', FALSE, NULL),
    (8, 2, 1, 'Помидоры', 1.00, 'кг', FALSE, NULL),
    (9, 2, 1, 'Огурцы', 0.80, 'кг', FALSE, NULL),
    (10, 2, 3, 'Кефир', 1.00, 'л', TRUE, CURRENT_TIMESTAMP - INTERVAL '3 hours'),
    (11, 3, 7, 'Стиральный порошок', 1.00, 'уп.', FALSE, NULL),
    (12, 3, 7, 'Губки для посуды', 3.00, 'шт.', TRUE, CURRENT_TIMESTAMP - INTERVAL '2 days'),
    (13, 4, 5, 'Овсяные хлопья', 500.00, 'г', FALSE, NULL),
    (14, 4, 2, 'Бананы', 6.00, 'шт.', FALSE, NULL),
    (15, 4, 3, 'Йогурт', 4.00, 'шт.', FALSE, NULL),
    (16, 4, 5, 'Хлеб', 1.00, 'буханка', TRUE, CURRENT_TIMESTAMP - INTERVAL '4 hours');

-- После явного указания идентификаторов синхронизируем последовательности.
SELECT setval(pg_get_serial_sequence('users', 'user_id'),
              (SELECT MAX(user_id) FROM users));
SELECT setval(pg_get_serial_sequence('categories', 'category_id'),
              (SELECT MAX(category_id) FROM categories));
SELECT setval(pg_get_serial_sequence('shopping_lists', 'list_id'),
              (SELECT MAX(list_id) FROM shopping_lists));
SELECT setval(pg_get_serial_sequence('items', 'item_id'),
              (SELECT MAX(item_id) FROM items));

-- Проверка количества записей
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'account_activation_tokens', COUNT(*) FROM account_activation_tokens
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'shopping_lists', COUNT(*) FROM shopping_lists
UNION ALL SELECT 'items', COUNT(*) FROM items;

COMMIT;
