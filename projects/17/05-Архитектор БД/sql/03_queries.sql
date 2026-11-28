-- ============================================================
-- Основные SQL-запросы веб-сервиса онлайн-записи «Окошко»
-- ============================================================

-- ============================================================
-- 1. УЧЁТНЫЕ ЗАПИСИ, АКТИВАЦИЯ И ПРИВЯЗКА TELEGRAM
-- ============================================================

-- Регистрация новой учётной записи (до подтверждения email)
INSERT INTO web_accounts (name, email, password_hash, role, status, privacy_accepted_at)
VALUES ('Иван Петров', 'ivan@example.com', 'scrypt$16384$8$1$salt_ivn$hash_ivn_07', 'user', 'inactive', CURRENT_TIMESTAMP);

-- Активация учётной записи по действующему токену
UPDATE web_accounts
SET status = 'active'
WHERE account_id = (
    SELECT account_id
    FROM tokens
    WHERE purpose = 'activate'
      AND token_hash = 'a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001'
      AND used_at IS NULL
      AND expires_at > CURRENT_TIMESTAMP
);

-- Проверка учётной записи при входе по email
SELECT account_id, name, email, role, status
FROM web_accounts
WHERE email = 'maria@example.com' AND status = 'active';

-- Получение привязки Telegram для учётной записи пользователя
SELECT a.account_id, a.name, a.email, tl.tg_user_id, tl.tg_username, tl.linked_at
FROM web_accounts a
LEFT JOIN telegram_links tl ON a.account_id = tl.account_id
WHERE a.account_id = 4;

-- ============================================================
-- 2. МАСТЕРА, ЛИЧНЫЕ САЙТЫ И ПРАЙС-ЛИСТ
-- ============================================================

-- Открытие личного сайта мастера по короткому адресу (slug)
SELECT m.master_id, m.public_id, m.master_name, m.specialty, m.address_text,
       m.timezone, m.manual_confirm, ms.slug, ms.palette, ms.headline, ms.about_text,
       mb.bot_username
FROM masters m
INNER JOIN master_sites ms ON m.master_id = ms.master_id
LEFT JOIN master_bots mb ON m.master_id = mb.master_id AND mb.status = 'active'
WHERE ms.slug = 'anna-nails' AND ms.is_published = 1 AND m.status = 'active';

-- Получение активного прайс-листа мастера
SELECT service_id, title, category, duration_min, buffer_after_min,
       price_from, price_to, price_type
FROM services
WHERE master_id = 1 AND is_active = 1
ORDER BY sort_order, service_id;

-- Добавление новой услуги в прайс мастера
INSERT INTO services (master_id, title, category, duration_min, buffer_after_min, price_from, price_type, sort_order)
VALUES (1, 'Укрепление ногтей гелем', 'Маникюр', 40, 10, 900, 'exact', 5);

-- ============================================================
-- 3. ГРАФИК РАБОТЫ И БЛОКИРОВКИ ВРЕМЕНИ
-- ============================================================

-- Получение графика работы мастера и его блокировок на период
SELECT m.master_name, ws.weekly_hours_json, ws.slot_step_min, ws.horizon_days,
       tb.start_at AS block_start, tb.end_at AS block_end, tb.reason, tb.note
FROM masters m
INNER JOIN work_schedules ws ON m.master_id = ws.master_id
LEFT JOIN time_blocks tb ON ws.schedule_id = tb.schedule_id
                        AND tb.end_at >= '2026-11-28 00:00:00'
WHERE m.master_id = 1
ORDER BY tb.start_at;

-- Добавление новой блокировки времени в график мастера
INSERT INTO time_blocks (schedule_id, start_at, end_at, reason, note)
VALUES (1, '2026-12-08 12:00:00', '2026-12-08 14:00:00', 'personal', 'Личные дела');

-- ============================================================
-- 4. ЗАПИСИ КЛИЕНТОВ И КЛИЕНТСКАЯ БАЗА
-- ============================================================

-- Проверка занятых активных слотов мастера на дату (для расчёта свободных окон)
SELECT booking_id, start_at, end_at, status
FROM bookings
WHERE master_id = 1
  AND status IN ('pending', 'confirmed')
  AND start_at >= '2026-11-28 00:00:00'
  AND start_at <  '2026-11-29 00:00:00'
ORDER BY start_at;

-- Личный кабинет клиента: все записи ко всем мастерам с составом услуг
SELECT b.booking_id, m.master_name, ms.slug, b.start_at, b.end_at,
       b.status, b.source, b.total_price,
       GROUP_CONCAT(bs.service_title_snapshot, ' + ') AS services_list
FROM bookings b
INNER JOIN client_cards cc ON b.client_card_id = cc.client_card_id
INNER JOIN masters m ON b.master_id = m.master_id
LEFT JOIN master_sites ms ON m.master_id = ms.master_id
INNER JOIN booking_services bs ON b.booking_id = bs.booking_id
WHERE cc.account_id = 4
GROUP BY b.booking_id, m.master_name, ms.slug, b.start_at, b.end_at, b.status, b.source, b.total_price
ORDER BY b.start_at DESC;

-- Подтверждение заявки мастером (при включённом ручном подтверждении)
UPDATE bookings
SET status = 'confirmed', updated_at = CURRENT_TIMESTAMP
WHERE booking_id = 4 AND master_id = 2 AND status = 'pending';

-- Поиск клиентов мастера с количеством визитов (для базы клиентов и экспорта в Excel)
SELECT cc.client_card_id, cc.display_name, cc.phone, cc.birthday, cc.note,
       COUNT(b.booking_id) AS bookings_count,
       MAX(b.start_at) AS last_visit_at
FROM client_cards cc
LEFT JOIN bookings b ON cc.client_card_id = b.client_card_id
                    AND b.status IN ('confirmed', 'completed')
WHERE cc.master_id = 1 AND cc.is_banned = 0
GROUP BY cc.client_card_id, cc.display_name, cc.phone, cc.birthday, cc.note
ORDER BY last_visit_at DESC;

-- ============================================================
-- 5. УВЕДОМЛЕНИЯ НА САЙТЕ И ОЧЕРЕДЬ ДОСТАВКИ
-- ============================================================

-- Непрочитанные уведомления пользователя в шапке сайта
SELECT notification_id, recipient_role, event_type, title, body, action_link, created_at
FROM notifications
WHERE account_id = 4 AND channel = 'web' AND is_read = 0
ORDER BY created_at DESC;

-- Отметка уведомлений пользователя как прочитанных
UPDATE notifications
SET is_read = 1
WHERE account_id = 4 AND channel = 'web' AND is_read = 0;

-- ============================================================
-- 6. СТАТИСТИКА И ОТЧЁТЫ
-- ============================================================

-- Выручка, число записей и средний чек по мастерам
SELECT m.master_name,
       COUNT(b.booking_id) AS total_bookings,
       SUM(CASE WHEN b.status IN ('confirmed', 'completed') THEN 1 ELSE 0 END) AS active_or_done,
       COALESCE(SUM(CASE WHEN b.status IN ('confirmed', 'completed') THEN b.total_price ELSE 0 END), 0) AS revenue_rub,
       ROUND(AVG(CASE WHEN b.status IN ('confirmed', 'completed') THEN b.total_price END), 2) AS avg_check_rub
FROM masters m
LEFT JOIN bookings b ON m.master_id = b.master_id
GROUP BY m.master_id, m.master_name
ORDER BY revenue_rub DESC;

-- Популярность услуг по числу включений в записи
SELECT s.title, s.category, COUNT(bs.booking_service_id) AS times_booked,
       COALESCE(SUM(bs.price_snapshot), 0) AS total_amount_rub
FROM services s
LEFT JOIN booking_services bs ON s.service_id = bs.service_id
WHERE s.master_id = 1
GROUP BY s.service_id, s.title, s.category
ORDER BY times_booked DESC, total_amount_rub DESC;

-- Распределение записей по каналам (сайт, Telegram, ручная запись)
SELECT source, COUNT(*) AS bookings_count
FROM bookings
GROUP BY source
ORDER BY bookings_count DESC;
