-- Выполнить один раз после 01_create_database.sql.
-- Все пользователи и расходы вымышлены. Пароли с префиксом ! непригодны
-- для входа в Django: это данные для проверки БД, не готовые аккаунты.
-- Октябрь пользователя demo_a: 510 + 90 + 120 = 720 рублей.

BEGIN;

INSERT INTO auth_user
    (id, username, password, first_name, last_name, email,
     is_superuser, is_staff, is_active, date_joined)
VALUES
    (1, 'demo_a', '!demo-a', '', '', '', false, false, true,
     '2026-09-01 10:00:00+03'),
    (2, 'demo_b', '!demo-b', '', '', '', false, false, true,
     '2026-09-02 10:00:00+03');

INSERT INTO finance_revision (user_id, revision) VALUES (1, 4), (2, 1);

INSERT INTO finance_category (id, user_id, name, is_archived) VALUES
    (1, 1, 'Продукты', false),
    (2, 1, 'Транспорт', false),
    (3, 1, 'Развлечения', true),
    (4, 2, 'Продукты', false),
    (5, 2, 'Транспорт', false);

INSERT INTO finance_expense
    (id, user_id, category_id, amount_minor, expense_date, comment,
     created_at, updated_at)
VALUES
    (1, 1, 1, 51000, '2026-10-01', 'Покупка продуктов',
     '2026-10-01 18:00:00+03', '2026-10-01 18:00:00+03'),
    (2, 1, 2,  9000, '2026-10-02', 'Поездка',
     '2026-10-02 09:00:00+03', '2026-10-02 09:00:00+03'),
    (3, 1, 1, 12000, '2026-10-03', 'Покупка продуктов',
     '2026-10-03 19:00:00+03', '2026-10-03 19:00:00+03'),
    (4, 1, 1, 20000, '2026-09-30', 'Расход другого месяца',
     '2026-09-30 18:00:00+03', '2026-09-30 18:00:00+03'),
    (5, 2, 4, 99999, '2026-10-10', 'Расход другого пользователя',
     '2026-10-10 18:00:00+03', '2026-10-10 18:00:00+03');

-- Явные id выше не передвигают identity-последовательности автоматически.
SELECT setval(pg_get_serial_sequence('auth_user', 'id'),
              (SELECT max(id) FROM auth_user));
SELECT setval(pg_get_serial_sequence('finance_category', 'id'),
              (SELECT max(id) FROM finance_category));
SELECT setval(pg_get_serial_sequence('finance_expense', 'id'),
              (SELECT max(id) FROM finance_expense));

-- Сессию создаёт Django при входе; фиктивное session_data не записываем.
COMMIT;

SELECT 'auth_user' AS table_name, count(*) AS row_count FROM auth_user
UNION ALL SELECT 'finance_revision', count(*) FROM finance_revision
UNION ALL SELECT 'finance_category', count(*) FROM finance_category
UNION ALL SELECT 'finance_expense', count(*) FROM finance_expense
UNION ALL SELECT 'django_session', count(*) FROM django_session;
