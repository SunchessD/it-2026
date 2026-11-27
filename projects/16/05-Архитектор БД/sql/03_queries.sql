-- Примеры запросов после 01_create_database.sql и 02_test_data.sql.
-- Здесь user_id = 1 и даты заданы явно для воспроизводимого результата.
-- В приложении владелец берётся из сессии, значения передаются параметрами.
-- Все примеры изменения заканчиваются ROLLBACK: исходный набор сохраняется.

-- Q01. Активные категории для нового расхода (UC-05).
SELECT id, name
FROM finance_category
WHERE user_id = 1 AND NOT is_archived
ORDER BY lower(name), id;

-- Q02. Первая страница расходов за включительный диапазон (UC-04).
-- При фильтре категории добавляется AND e.category_id = <параметр>.
SELECT e.id, e.expense_date, c.name AS category,
       e.amount_minor, e.amount_minor::numeric / 100 AS amount_rub, e.comment
FROM finance_expense e
JOIN finance_category c ON (c.id, c.user_id) = (e.category_id, e.user_id)
WHERE e.user_id = 1
  AND e.expense_date BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
ORDER BY e.expense_date DESC, e.id DESC
LIMIT 20 OFFSET 0;

-- Q03. Сводка за месяц (UC-12): Продукты 630, Транспорт 90, итог 720.
-- Архивные категории с историей тоже входят в результат.
WITH category_totals AS (
    SELECT c.id, c.name, sum(e.amount_minor) AS total_minor
    FROM finance_expense e
    JOIN finance_category c ON (c.id, c.user_id) = (e.category_id, e.user_id)
    WHERE e.user_id = 1
      AND e.expense_date >= DATE '2026-10-01'
      AND e.expense_date < DATE '2026-11-01'
    GROUP BY c.id, c.name
)
SELECT id, name, total_minor, total_minor / 100 AS amount_rub,
       sum(total_minor) OVER () / 100 AS month_total_rub,
       round(100 * total_minor / sum(total_minor) OVER (), 1) AS share_percent
FROM category_totals
ORDER BY id;

-- Q04. Пустой месяц: ноль, а не NULL; строк категорий у него нет.
SELECT coalesce(sum(amount_minor), 0) AS total_minor
FROM finance_expense
WHERE user_id = 1
  AND expense_date >= DATE '2026-11-01'
  AND expense_date < DATE '2026-12-01';

-- Q05. Ревизия и пример ключа кэша. В Redis обращается приложение.
SELECT revision,
       'expenses:v1:u:' || user_id || ':r:' || revision || ':m:2026-10' AS cache_key
FROM finance_revision WHERE user_id = 1;

-- Q06. Новый расход 80 рублей и увеличение ревизии (UC-05).
-- Блокировка категории согласована с операцией её архивирования.
-- Нулевая строка результата означает, что запись не была создана:
-- приложение должно сообщить об ошибке выбора категории или состояния счётчика.
BEGIN;
WITH allowed_category AS (
    SELECT c.id, c.user_id
    FROM finance_category c
    JOIN finance_revision r ON r.user_id = c.user_id
    WHERE c.id = 1 AND c.user_id = 1 AND NOT c.is_archived
    FOR UPDATE OF c
), added AS (
    INSERT INTO finance_expense
        (user_id, category_id, amount_minor, expense_date, comment)
    SELECT user_id, id, 8000, DATE '2026-10-04', 'Дополнительная покупка'
    FROM allowed_category
    RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM added a WHERE r.user_id = a.user_id
RETURNING r.user_id, r.revision;

-- Внутри транзакции: 800 рублей и ревизия 5.
SELECT sum(e.amount_minor) / 100 AS total_rub, r.revision
FROM finance_expense e
JOIN finance_revision r ON r.user_id = e.user_id
WHERE e.user_id = 1
  AND e.expense_date >= DATE '2026-10-01'
  AND e.expense_date < DATE '2026-11-01'
GROUP BY r.revision;
ROLLBACK;

-- Q07. Исправление суммы своего расхода (UC-06).
-- Категория остаётся прежней. При её смене нужны проверки и блокировка Q06.
BEGIN;
WITH changed AS (
    UPDATE finance_expense
    SET amount_minor = 12500, updated_at = CURRENT_TIMESTAMP
    WHERE id = 3 AND user_id = 1
    RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM changed e WHERE r.user_id = e.user_id
RETURNING r.revision;
SELECT id, amount_minor, updated_at FROM finance_expense
WHERE id = 3 AND user_id = 1;
ROLLBACK;

-- Q08. Удаление своего расхода после подтверждения (UC-07).
BEGIN;
WITH removed AS (
    DELETE FROM finance_expense WHERE id = 3 AND user_id = 1
    RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM removed e WHERE r.user_id = e.user_id
RETURNING r.revision;
ROLLBACK;

-- Q09. Создание категории (UC-08).
BEGIN;
WITH added AS (
    INSERT INTO finance_category (user_id, name)
    VALUES (1, 'Здоровье') RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM added c WHERE r.user_id = c.user_id
RETURNING r.revision;
ROLLBACK;

-- Q10. Переименование меняет название и в истории (UC-09).
BEGIN;
WITH changed AS (
    UPDATE finance_category SET name = 'Покупки'
    WHERE id = 1 AND user_id = 1 RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM changed c WHERE r.user_id = c.user_id
RETURNING r.revision;
ROLLBACK;

-- Q11. Архивирование (UC-10); восстановление использует is_archived = false.
-- UPDATE блокирует ту же строку, которую Q06 читает FOR UPDATE.
BEGIN;
WITH changed AS (
    UPDATE finance_category SET is_archived = true
    WHERE id = 2 AND user_id = 1 AND NOT is_archived
    RETURNING user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM changed c WHERE r.user_id = c.user_id
RETURNING r.revision;
SELECT c.name, c.is_archived, count(e.id) AS saved_expenses
FROM finance_category c
LEFT JOIN finance_expense e ON (e.category_id, e.user_id) = (c.id, c.user_id)
WHERE c.id = 2 AND c.user_id = 1
GROUP BY c.id;
ROLLBACK;

-- Q12. Удаление пустой категории (UC-11).
-- NOT EXISTS даёт понятный результат, FK дополнительно защищает от гонки.
BEGIN;
WITH removed AS (
    DELETE FROM finance_category c
    WHERE c.id = 3 AND c.user_id = 1
      AND NOT EXISTS (
          SELECT 1 FROM finance_expense e
          WHERE (e.category_id, e.user_id) = (c.id, c.user_id)
      )
    RETURNING c.user_id
)
UPDATE finance_revision r SET revision = r.revision + 1
FROM removed c WHERE r.user_id = c.user_id
RETURNING r.revision;
ROLLBACK;

-- Q13. Регистрация: аккаунт, ревизия 0 и начальные категории (UC-01).
-- Здесь пароль намеренно непригоден для входа. Настоящий хэш создаёт Django.
BEGIN;
WITH new_user AS (
    INSERT INTO auth_user
        (username, password, first_name, last_name, email,
         is_superuser, is_staff, is_active, date_joined)
    VALUES ('demo_new', '!demo-new', '', '', '', false, false, true, CURRENT_TIMESTAMP)
    RETURNING id
), new_revision AS (
    INSERT INTO finance_revision (user_id)
    SELECT id FROM new_user RETURNING user_id
)
INSERT INTO finance_category (user_id, name)
SELECT r.user_id, c.name
FROM new_revision r CROSS JOIN (VALUES ('Продукты'), ('Транспорт')) AS c(name)
RETURNING id, user_id, name;
ROLLBACK;

-- Контроль: после всех примеров исходные значения снова 720 и 4.
SELECT sum(e.amount_minor) / 100 AS total_rub, r.revision
FROM finance_expense e JOIN finance_revision r ON r.user_id = e.user_id
WHERE e.user_id = 1
  AND e.expense_date >= DATE '2026-10-01'
  AND e.expense_date < DATE '2026-11-01'
GROUP BY r.revision;
