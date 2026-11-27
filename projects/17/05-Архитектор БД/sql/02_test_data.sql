-- ============================================================
-- Тестовые данные веб-сервиса онлайн-записи «Окошко»
-- Порядок заполнения соответствует зависимостям FOREIGN KEY
-- ============================================================

PRAGMA foreign_keys = ON;

-- 1. УЧЁТНЫЕ ЗАПИСИ (web_accounts)
INSERT INTO web_accounts (name, email, password_hash, role, status, privacy_accepted_at, last_login_at) VALUES
    ('Администратор сервиса', 'admin@okoshko.site', 'scrypt$16384$8$1$salt_adm$hash_adm_01', 'admin', 'active', '2026-10-01 09:00:00', '2026-11-26 10:00:00'),
    ('Анна Смирнова',         'anna@okoshko.site',  'scrypt$16384$8$1$salt_ann$hash_ann_02', 'user',  'active', '2026-10-05 11:20:00', '2026-11-26 18:15:00'),
    ('Дмитрий Волков',        'dmitry@okoshko.site','scrypt$16384$8$1$salt_dmt$hash_dmt_03', 'user',  'active', '2026-10-10 14:00:00', '2026-11-25 20:30:00'),
    ('Мария Соколова',        'maria@example.com',  'scrypt$16384$8$1$salt_mar$hash_mar_04', 'user',  'active', '2026-11-01 12:10:00', '2026-11-26 19:00:00'),
    ('Ольга Кузнецова',       'olga@example.com',   'scrypt$16384$8$1$salt_olg$hash_olg_05', 'user',  'active', '2026-11-05 16:40:00', '2026-11-24 17:10:00'),
    ('Елена Морозова',        'elena@example.com',  'scrypt$16384$8$1$salt_eln$hash_eln_06', 'user',  'inactive','2026-11-26 20:00:00', NULL);

-- 2. ТОКЕНЫ (tokens)
INSERT INTO tokens (account_id, purpose, token_hash, expires_at, used_at) VALUES
    (6, 'activate', 'a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001', '2026-11-27 20:00:00', NULL),
    (4, 'tg_link',  'b2c3d4e5f60002b2c3d4e5f60002b2c3d4e5f60002b2c3d4e5f60002b2c3d4e5', '2026-11-01 12:30:00', '2026-11-01 12:18:00');

-- 3. ВЕБ-СЕССИИ (web_sessions)
INSERT INTO web_sessions (account_id, token_hash, expires_at, last_seen_at, revoked_at) VALUES
    (2, 's100000000000000000000000000000000000000000000000000000000000002', '2026-12-26 18:15:00', '2026-11-26 18:15:00', NULL),
    (4, 's100000000000000000000000000000000000000000000000000000000000004', '2026-12-26 19:00:00', '2026-11-26 19:00:00', NULL);

-- 4. ПРИВЯЗКИ TELEGRAM (telegram_links)
INSERT INTO telegram_links (account_id, tg_user_id, tg_name, tg_username) VALUES
    (2, 501002003, 'Анна Маникюр', 'anna_nails_spb'),
    (4, 504005006, 'Мария С.',     'maria_sokolova');

-- 5. МАСТЕРА (masters)
INSERT INTO masters (owner_account_id, public_id, master_name, specialty, address_text, address_mode, timezone, manual_confirm, status) VALUES
    (2, 'annasmirn01', 'Анна Смирнова',  'Маникюр и педикюр',   'Санкт-Петербург, Невский пр., 78, каб. 14', 'place', 'Europe/Moscow', 0, 'active'),
    (3, 'dmitryvol02', 'Дмитрий Волков', 'Мужские стрижки',     'Санкт-Петербург, ул. Рубинштейна, 22',      'place', 'Europe/Moscow', 1, 'active');

-- 6. ЛИЧНЫЕ САЙТЫ МАСТЕРОВ (master_sites)
INSERT INTO master_sites (master_id, slug, palette, headline, about_text, is_published) VALUES
    (1, 'anna-nails',    'rose',  'Маникюр и педикюр в центре Санкт-Петербурга', 'Работаю со стерильным инструментом, аккуратное покрытие с гарантией 14 дней.', 1),
    (2, 'barber-dmitry', 'ocean', 'Стрижки и оформление бороды без очередей',     'Индивидуальный подбор формы, запись онлайн на удобное время.', 1);

-- 7. БОТЫ МАСТЕРОВ (master_bots: у Анны подключён бот, Дмитрий работает только через сайт)
INSERT INTO master_bots (master_id, tg_bot_id, bot_username, token_enc, status) VALUES
    (1, 7901234567, 'anna_nails_okoshko_bot', 'gAAAAABm_encrypted_fernet_token_example_01', 'active');

-- 8. УСЛУГИ МАСТЕРОВ (services)
INSERT INTO services (master_id, title, category, duration_min, buffer_after_min, price_from, price_to, price_type, is_active, sort_order) VALUES
    (1, 'Маникюр с покрытием гель-лак', 'Маникюр',  90, 15, 2200, NULL, 'exact',  1, 1),
    (1, 'Снятие покрытия',              'Маникюр',  20, 0,  400,  NULL, 'exact',  1, 2),
    (1, 'Дизайн ногтей',                'Маникюр',  30, 0,  500,  1200, 'range',  1, 3),
    (1, 'Педикюр классический',         'Педикюр',  75, 15, 2500, NULL, 'from',   1, 4),
    (2, 'Мужская стрижка',              'Стрижки',  45, 10, 1800, NULL, 'exact',  1, 1),
    (2, 'Оформление бороды',            'Борода',   30, 5,  1000, NULL, 'exact',  1, 2),
    (2, 'Консультация стилиста',        'Стрижки',  60, 0,  1500, NULL, 'hourly', 1, 3);

-- 9. ГРАФИКИ РАБОТЫ (work_schedules: несколько перерывов внутри дня)
INSERT INTO work_schedules (master_id, weekly_hours_json, slot_step_min, horizon_days, min_notice_min, cancel_limit_hours) VALUES
    (1, '{"mon":[["10:00","13:00"],["14:00","17:00"],["17:30","20:00"]],"tue":[["10:00","13:00"],["14:00","19:00"]],"wed":[["10:00","14:00"],["15:00","20:00"]],"thu":[["10:00","13:00"],["14:00","19:00"]],"fri":[["10:00","13:00"],["14:00","18:00"]],"sat":[["11:00","16:00"]],"sun":[]}', 30, 30, 60, 3),
    (2, '{"mon":[["11:00","14:00"],["15:00","21:00"]],"tue":[["11:00","14:00"],["15:00","21:00"]],"wed":[],"thu":[["11:00","14:00"],["15:00","21:00"]],"fri":[["11:00","14:00"],["15:00","21:00"]],"sat":[["11:00","19:00"]],"sun":[]}', 30, 14, 120, 4);

-- 10. БЛОКИРОВКИ ВРЕМЕНИ (time_blocks)
INSERT INTO time_blocks (schedule_id, start_at, end_at, reason, note) VALUES
    (1, '2026-12-05 14:00:00', '2026-12-05 17:00:00', 'personal', 'Обучение новым материалам'),
    (2, '2026-12-10 00:00:00', '2026-12-13 23:59:00', 'vacation', 'Отпуск');

-- 11. КАРТОЧКИ КЛИЕНТОВ (client_cards)
INSERT INTO client_cards (master_id, account_id, tg_user_id, display_name, phone, consent_at, birthday, note, is_banned) VALUES
    (1, 4,    504005006, 'Мария Соколова',  '+79112223344', '2026-11-01 12:15:00', '05-14', 'Любит нюдовые оттенки', 0),
    (1, 5,    NULL,      'Ольга Кузнецова', '+79115556677', '2026-11-05 16:45:00', '09-22', 'Предпочитает утренние окна', 0),
    (1, NULL, 509887766, 'Светлана Орлова', '+79213334455', '2026-11-10 10:05:00', NULL,    'Записалась через Telegram-бот', 0),
    (2, 4,    504005006, 'Мария Соколова',  '+79112223344', '2026-11-20 15:00:00', NULL,    'Запись для брата', 0);

-- 12. ЗАПИСИ (bookings)
INSERT INTO bookings (master_id, client_card_id, start_at, end_at, total_duration_min, total_price, status, source, comment, idem_key) VALUES
    (1, 1, '2026-11-28 10:00:00', '2026-11-28 11:50:00', 110, 2600, 'confirmed', 'web',      'Снятие старого покрытия и светлый нюд', 'idem-bk-20261128-01'),
    (1, 2, '2026-11-28 14:00:00', '2026-11-28 15:15:00', 75,  2500, 'confirmed', 'web',      NULL,                                    'idem-bk-20261128-02'),
    (1, 3, '2026-11-20 11:00:00', '2026-11-20 12:30:00', 90,  2200, 'completed', 'telegram', 'Запись через бот',                      'idem-bk-20261120-03'),
    (2, 4, '2026-11-29 15:00:00', '2026-11-29 15:45:00', 45,  1800, 'pending',   'web',      'Классическая стрижка',                  'idem-bk-20261129-04');

-- 13. УСЛУГИ В ЗАПИСЯХ (booking_services: запись #1 - комбо из 2 услуг)
INSERT INTO booking_services (booking_id, service_id, service_title_snapshot, duration_min_snapshot, price_snapshot) VALUES
    (1, 1, 'Маникюр с покрытием гель-лак', 90, 2200),
    (1, 2, 'Снятие покрытия',              20, 400),
    (2, 4, 'Педикюр классический',         75, 2500),
    (3, 1, 'Маникюр с покрытием гель-лак', 90, 2200),
    (4, 5, 'Мужская стрижка',              45, 1800);

-- 14. УВЕДОМЛЕНИЯ (notifications: web, email, telegram)
INSERT INTO notifications (booking_id, account_id, channel, recipient_role, event_type, title, body, delivery_status, is_read, action_link, recipient_email, recipient_tg_id, sent_at) VALUES
    (1, 4, 'web',      'client', 'confirmed', 'Вы записаны к мастеру Анна Смирнова', '28.11.2026 в 10:00 - Маникюр с покрытием гель-лак + Снятие покрытия', 'sent', 0, '/me', NULL, NULL, '2026-11-26 19:01:00'),
    (1, 2, 'web',      'master', 'created',   'Новая запись на сайте',               'Мария Соколова записалась на 28.11.2026 в 10:00',                    'sent', 0, '/studio/bookings', NULL, NULL, '2026-11-26 19:01:00'),
    (1, 4, 'email',    'client', 'confirmed', 'Подтверждение записи - Окошко',       'Ждём вас 28.11.2026 в 10:00 по адресу: Невский пр., 78, каб. 14',    'sent', 0, NULL, 'maria@example.com', NULL, '2026-11-26 19:01:05'),
    (1, 2, 'telegram', 'master', 'created',   'Новая запись через сайт',             'Мария Соколова (+79112223344), 28.11.2026 10:00, 2600 руб.',         'sent', 0, NULL, NULL, 501002003, '2026-11-26 19:01:02'),
    (4, 3, 'web',      'master', 'pending',   'Заявка ожидает подтверждения',        'Мария Соколова запросила запись на 29.11.2026 в 15:00',              'sent', 0, '/studio/bookings', NULL, NULL, '2026-11-26 19:10:00'),
    (4, 3, 'email',    'master', 'pending',   'Новая заявка на запись - Окошко',     'Подтвердите или отклоните заявку на 29.11.2026 в 15:00 в кабинете.', 'sent', 0, NULL, 'dmitry@okoshko.site', NULL, '2026-11-26 19:10:03');

-- Проверка наполнения таблиц
SELECT 'web_accounts'     AS table_name, COUNT(*) AS row_count FROM web_accounts
UNION ALL SELECT 'tokens',           COUNT(*) FROM tokens
UNION ALL SELECT 'web_sessions',     COUNT(*) FROM web_sessions
UNION ALL SELECT 'telegram_links',   COUNT(*) FROM telegram_links
UNION ALL SELECT 'masters',          COUNT(*) FROM masters
UNION ALL SELECT 'master_sites',     COUNT(*) FROM master_sites
UNION ALL SELECT 'master_bots',      COUNT(*) FROM master_bots
UNION ALL SELECT 'services',         COUNT(*) FROM services
UNION ALL SELECT 'work_schedules',   COUNT(*) FROM work_schedules
UNION ALL SELECT 'time_blocks',      COUNT(*) FROM time_blocks
UNION ALL SELECT 'client_cards',     COUNT(*) FROM client_cards
UNION ALL SELECT 'bookings',         COUNT(*) FROM bookings
UNION ALL SELECT 'booking_services', COUNT(*) FROM booking_services
UNION ALL SELECT 'notifications',    COUNT(*) FROM notifications;
