BEGIN;
SET search_path TO stylestore, public;

INSERT INTO "Пользователь" ("имя", "email", "хеш_пароля")
VALUES ('Наталья Новикова', 'Natalia@Example.Test', 'pbkdf2_sha256$260000$StyleStore_2026$DAoC87i+YbB0s4hQ+ia1Ab7i0kcHX0UgySKEAd2WFvk=')
RETURNING "id_пользователя", "имя", "email", "статус_аккаунта";

INSERT INTO "Покупатель" ("id_пользователя")
SELECT "id_пользователя" FROM "Пользователь" WHERE "email" = 'natalia@example.test';

INSERT INTO "Токен_аккаунта" ("хеш_токена", "id_пользователя", "назначение", "истекает_в")
SELECT '30bb93b6d7b6816a8d7973aa22e28c1034db8811a347361e955df7604491c046', "id_пользователя", 'activation', CURRENT_TIMESTAMP + INTERVAL '1 day'
FROM "Пользователь" WHERE "email" = 'natalia@example.test';

WITH действующий_токен AS (
    UPDATE "Токен_аккаунта" SET "использован_в" = CURRENT_TIMESTAMP
    WHERE "хеш_токена" = '30bb93b6d7b6816a8d7973aa22e28c1034db8811a347361e955df7604491c046' AND "назначение" = 'activation'
      AND "использован_в" IS NULL AND "истекает_в" > CURRENT_TIMESTAMP
    RETURNING "id_пользователя"
)
UPDATE "Пользователь" u SET "статус_аккаунта" = 'active'
FROM действующий_токен t WHERE u."id_пользователя" = t."id_пользователя"
RETURNING u."id_пользователя", u."email", u."статус_аккаунта";

SELECT "id_пользователя", "имя", "email", "хеш_пароля"
FROM "Пользователь"
WHERE "email" = lower('ANNA@EXAMPLE.TEST') AND "статус_аккаунта" = 'active';

WITH действующий_токен AS (
    UPDATE "Токен_аккаунта" SET "использован_в" = CURRENT_TIMESTAMP
    WHERE "хеш_токена" = 'af62879595bc43de3c15e883c7730297cb162225c055b29843545c382db82539' AND "назначение" = 'password_reset'
      AND "использован_в" IS NULL AND "истекает_в" > CURRENT_TIMESTAMP
    RETURNING "id_пользователя"
)
UPDATE "Пользователь" u SET "хеш_пароля" = 'pbkdf2_sha256$260000$StyleStore_2026$ZqTD5QRrLIOh3rcTBA0ihHxHETBSTSqTN3e2BA6v93w='
FROM действующий_токен t WHERE u."id_пользователя" = t."id_пользователя"
RETURNING u."id_пользователя", u."email";

UPDATE "Покупатель" SET "телефон" = '+7 900 111-22-33',
    "адрес_по_умолчанию" = 'Санкт-Петербург, Литейный проспект, 15'
WHERE "id_пользователя" = 1
RETURNING *;

SELECT c."id_категории", c."название", COUNT(t."id_товара") AS "опубликовано_моделей"
FROM "Категория" c LEFT JOIN "Товар" t
ON t."id_категории" = c."id_категории" AND t."опубликован"
GROUP BY c."id_категории", c."название" ORDER BY c."id_категории";

SELECT t."id_товара", t."артикул", t."название", c."название" AS "категория", t."цена", t."прежняя_цена", t."фотография"
FROM "Товар" t JOIN "Категория" c USING ("id_категории")
WHERE t."опубликован" ORDER BY t."id_товара";

SELECT "id_товара", "название", "цена"
FROM "Товар"
WHERE "опубликован" AND ("название" ILIKE '%куртка%' OR "описание" ILIKE '%куртка%')
ORDER BY "цена", "id_товара";

SELECT "id_товара", "название", "цена"
FROM "Товар"
WHERE "опубликован"
  AND to_tsvector('russian', "название" || ' ' || "описание") @@ plainto_tsquery('russian', 'куртка')
ORDER BY "цена", "id_товара";

SELECT t."id_товара", t."название", t."цена"
FROM "Товар" t
WHERE t."опубликован" AND t."id_категории" = 1 AND t."цена" BETWEEN 2000 AND 8000
  AND EXISTS (
      SELECT 1 FROM "Вариант_товара" v WHERE v."id_товара" = t."id_товара"
      AND v."размер" = 'M' AND v."цвет" = 'Молочный' AND v."доступный_остаток" > 0
  )
ORDER BY t."цена", t."id_товара";

SELECT t."название", t."описание", t."цена", t."прежняя_цена", t."фотография",
       v."id_варианта", v."цвет", v."размер", v."доступный_остаток"
FROM "Товар" t JOIN "Вариант_товара" v USING ("id_товара")
WHERE t."id_товара" = 1 AND t."опубликован"
ORDER BY v."цвет", v."размер";

INSERT INTO "Позиция_избранного" ("id_избранного", "id_товара") VALUES (1, 7)
ON CONFLICT DO NOTHING RETURNING *;

SELECT t."id_товара", t."название", t."цена", p."дата_добавления"
FROM "Избранное" f JOIN "Позиция_избранного" p USING ("id_избранного")
JOIN "Товар" t USING ("id_товара")
WHERE f."id_пользователя" = 1 AND t."опубликован"
ORDER BY p."дата_добавления" DESC, t."id_товара";

DELETE FROM "Позиция_избранного"
WHERE "id_избранного" = 1 AND "id_товара" = 7 RETURNING *;

SELECT добавить_в_корзину(1, 2, 1);
SELECT добавить_в_корзину(1, 27, 1);

SELECT c."id_позиции_корзины", t."название", v."цвет", v."размер", c."количество",
       t."цена", t."цена" * c."количество" AS "стоимость_строки", v."доступный_остаток"
FROM "Позиция_корзины" c JOIN "Вариант_товара" v USING ("id_варианта")
JOIN "Товар" t USING ("id_товара") WHERE c."id_корзины" = 1 ORDER BY c."id_позиции_корзины";

UPDATE "Позиция_корзины" c SET "количество" = 2
FROM "Вариант_товара" v
WHERE c."id_корзины" = 1 AND c."id_варианта" = 2
  AND v."id_варианта" = c."id_варианта" AND v."доступный_остаток" >= 2
RETURNING c.*;

DELETE FROM "Позиция_корзины" WHERE "id_корзины" = 1 AND "id_варианта" = 27 RETURNING *;

WITH сумма AS (
    SELECT COALESCE(SUM(t."цена" * c."количество"), 0) AS "товары"
    FROM "Позиция_корзины" c JOIN "Вариант_товара" v USING ("id_варианта")
    JOIN "Товар" t USING ("id_товара") WHERE c."id_корзины" = 1
)
SELECT "товары", CASE WHEN "товары" >= 7990 OR "товары" = 0 THEN 0 ELSE 390 END AS "доставка",
       "товары" + CASE WHEN "товары" >= 7990 OR "товары" = 0 THEN 0 ELSE 390 END AS "итого_руб"
FROM сумма;

SELECT оформить_заказ(1, 'SS-2026-2001', 'courier', 'Санкт-Петербург', 'Литейный проспект, 15',
    'Анна Смирнова', '+7 900 111-22-33', 'anna@example.test', 'card', 'pay_query_2001') AS "id_заказа";

SELECT оформить_заказ(1, 'SS-2026-2001', 'courier', 'Санкт-Петербург', 'Литейный проспект, 15',
    'Анна Смирнова', '+7 900 111-22-33', 'anna@example.test', 'card', 'pay_query_2001') AS "id_заказа";

SELECT o."id_заказа", o."номер", o."дата_создания", o."статус", o."итоговая_сумма",
       d."способ" AS "способ_доставки", d."стоимость" AS "стоимость_доставки"
FROM "Заказ" o JOIN "Доставка" d USING ("id_заказа")
WHERE o."id_покупателя" = 1 ORDER BY o."дата_создания" DESC, o."id_заказа" DESC;

SELECT o."номер", i."название_модели", i."цвет", i."размер", i."количество", i."цена_на_момент_заказа",
       i."цена_на_момент_заказа" * i."количество" AS "стоимость_строки", r."состояние" AS "резерв"
FROM "Заказ" o JOIN "Позиция_заказа" i USING ("id_заказа")
LEFT JOIN "Резерв" r USING ("id_позиции_заказа")
WHERE o."номер" = 'SS-2026-2001' AND o."id_покупателя" = 1 ORDER BY i."id_позиции_заказа";

SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2001'), 'confirmed', 8);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2001'), 'packing', 8);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2001'), 'cancelled', 1);

SELECT e."статус", e."дата_время", u."имя" AS "автор"
FROM "Событие_заказа" e JOIN "Заказ" o USING ("id_заказа")
LEFT JOIN "Пользователь" u ON u."id_пользователя" = e."id_автора"
WHERE o."номер" = 'SS-2026-2001' ORDER BY e."дата_время", e."id_события";

SELECT "id_уведомления", "id_заказа", "текст", "время_отправки"
FROM "Уведомление" WHERE "id_пользователя" = 1 AND NOT "прочитано"
ORDER BY "время_отправки" DESC, "id_уведомления" DESC;

UPDATE "Уведомление" SET "прочитано" = TRUE
WHERE "id_пользователя" = 1 AND NOT "прочитано" RETURNING "id_уведомления", "прочитано";

SELECT "id_заказа", "номер", "статус", "имя_получателя", "итоговая_сумма"
FROM "Заказ" WHERE "статус" IN ('new', 'confirmed', 'packing')
ORDER BY "дата_создания", "id_заказа";

INSERT INTO "Категория" ("название", "описание")
VALUES ('Коллекция Limited', 'Ограниченная коллекция повседневной одежды.') RETURNING *;

INSERT INTO "Товар" ("id_категории", "артикул", "название", "описание", "фотография", "цена")
SELECT "id_категории", 'SS-0100', 'Толстовка свободного кроя Comfort',
       'Мягкая толстовка с капюшоном и карманом.', '/images/hoodie_comfort.jpg', 4990
FROM "Категория" WHERE "название" = 'Коллекция Limited'
RETURNING "id_товара", "артикул", "название", "цена", "опубликован";

INSERT INTO "Вариант_товара" ("id_товара", "цвет", "размер", "доступный_остаток")
SELECT t."id_товара", x."цвет", x."размер", x."остаток"
FROM "Товар" t CROSS JOIN (VALUES ('Серый', 'M', 12), ('Серый', 'L', 10), ('Молочный', 'M', 8)) x("цвет", "размер", "остаток")
WHERE t."артикул" = 'SS-0100' RETURNING *;

UPDATE "Товар" t SET "опубликован" = TRUE WHERE t."артикул" = 'SS-0100'
AND EXISTS (SELECT 1 FROM "Вариант_товара" v WHERE v."id_товара" = t."id_товара")
RETURNING t."артикул", t."опубликован";

UPDATE "Товар" SET "прежняя_цена" = "цена", "цена" = 4590
WHERE "артикул" = 'SS-0100' RETURNING "артикул", "цена", "прежняя_цена";

UPDATE "Вариант_товара" v SET "доступный_остаток" = 15
FROM "Товар" t WHERE v."id_товара" = t."id_товара"
AND t."артикул" = 'SS-0100' AND v."цвет" = 'Серый' AND v."размер" = 'M'
RETURNING v.*;

SELECT v."id_варианта", t."артикул", t."название", v."цвет", v."размер", v."доступный_остаток"
FROM "Вариант_товара" v JOIN "Товар" t USING ("id_товара")
WHERE v."доступный_остаток" <= 3 ORDER BY v."доступный_остаток", t."артикул", v."размер";

WITH резерв AS (
    SELECT i."id_варианта", SUM(r."количество") AS "зарезервировано"
    FROM "Резерв" r JOIN "Позиция_заказа" i USING ("id_позиции_заказа")
    WHERE r."состояние" = 'active' GROUP BY i."id_варианта"
)
SELECT t."артикул", v."цвет", v."размер", v."доступный_остаток",
       COALESCE(r."зарезервировано", 0) AS "зарезервировано",
       v."доступный_остаток" + COALESCE(r."зарезервировано", 0) AS "всего_на_складе"
FROM "Вариант_товара" v JOIN "Товар" t USING ("id_товара")
LEFT JOIN резерв r USING ("id_варианта") ORDER BY t."артикул", v."цвет", v."размер";

UPDATE "Товар" SET "опубликован" = FALSE WHERE "артикул" = 'SS-0100'
RETURNING "артикул", "опубликован";

SELECT добавить_в_корзину(4, 50, 1);
SELECT оформить_заказ(4, 'SS-2026-2002', 'courier', 'Санкт-Петербург', 'Невский проспект, 40',
    'Дмитрий Орлов', '+7 900 000-00-04', 'dmitry@example.test', 'receipt', NULL);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2002'), 'confirmed', 8);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2002'), 'packing', 8);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2002'), 'shipped', 8);
SELECT подтвердить_оплату((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2002'), 8);
SELECT изменить_статус_заказа((SELECT "id_заказа" FROM "Заказ" WHERE "номер" = 'SS-2026-2002'), 'delivered', 8);

SELECT o."номер", p."способ", p."сумма", p."состояние", p."id_операции"
FROM "Платёж" p JOIN "Заказ" o USING ("id_заказа")
WHERE p."состояние" = 'refund_pending' ORDER BY p."дата_операции", p."id_платежа";

UPDATE "Платёж" p SET "состояние" = 'refunded', "дата_операции" = CURRENT_TIMESTAMP
FROM "Заказ" o WHERE p."id_заказа" = o."id_заказа" AND o."номер" = 'SS-2026-2001'
AND p."состояние" = 'refund_pending'
RETURNING p."id_платежа", p."сумма", p."состояние";

SELECT "статус", COUNT(*) AS "заказов", SUM("итоговая_сумма") AS "сумма_руб"
FROM "Заказ" GROUP BY "статус" ORDER BY "статус";

SELECT DATE("дата_операции") AS "дата", COUNT(*) AS "успешных_оплат", SUM("сумма") AS "получено_руб"
FROM "Платёж" WHERE "состояние" = 'succeeded'
GROUP BY DATE("дата_операции") ORDER BY "дата";

SELECT c."название" AS "категория", SUM(i."количество") AS "продано_единиц",
       SUM(i."количество" * i."цена_на_момент_заказа") AS "стоимость_товаров_руб"
FROM "Заказ" o JOIN "Позиция_заказа" i USING ("id_заказа")
JOIN "Вариант_товара" v USING ("id_варианта") JOIN "Товар" t USING ("id_товара")
JOIN "Категория" c USING ("id_категории")
WHERE o."статус" = 'delivered'
GROUP BY c."id_категории", c."название" ORDER BY "стоимость_товаров_руб" DESC;

SELECT u."имя", COUNT(o."id_заказа") AS "заказов", COALESCE(SUM(o."итоговая_сумма"), 0) AS "сумма_руб"
FROM "Покупатель" b JOIN "Пользователь" u USING ("id_пользователя")
LEFT JOIN "Заказ" o ON o."id_покупателя" = b."id_пользователя" AND o."статус" <> 'cancelled'
GROUP BY u."id_пользователя", u."имя" ORDER BY "сумма_руб" DESC;

SELECT t."название", COUNT(*) AS "добавлений_в_избранное"
FROM "Позиция_избранного" f JOIN "Товар" t USING ("id_товара")
GROUP BY t."id_товара", t."название" ORDER BY "добавлений_в_избранное" DESC, t."id_товара";

SELECT o."номер", o."итоговая_сумма", SUM(i."количество" * i."цена_на_момент_заказа") + d."стоимость" AS "рассчитано_руб"
FROM "Заказ" o JOIN "Позиция_заказа" i USING ("id_заказа") JOIN "Доставка" d USING ("id_заказа")
GROUP BY o."id_заказа", o."номер", o."итоговая_сумма", d."стоимость"
HAVING o."итоговая_сумма" <> SUM(i."количество" * i."цена_на_момент_заказа") + d."стоимость";

ROLLBACK;
