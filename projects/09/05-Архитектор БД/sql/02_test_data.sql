-- Демонстрационные данные ReviewGuard.
-- Организация «Север» (1) и организация «Юг» (2) не видят данные друг друга.
-- Март 2026 у «Севера»: 11 датированных отзывов (3 позитивных, 2 нейтральных, 6 негативных).
-- Отдельно лежат февральский отзыв и отзыв без даты.

SET search_path TO reviewguard, public;

INSERT INTO organization (organization_id, name, data_revision) VALUES
    (1, 'Север', 2),
    (2, 'Юг', 1);

INSERT INTO account (account_id, organization_id, full_name, email, password_hash, role) VALUES
    (1, 1, 'Ирина Северная', 'irina@sever.example',
        '$argon2id$v=19$m=65536,t=3,p=4$c2FsdHNhbHRzYWx0MDE$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'organization_admin'),
    (2, 1, 'Павел Аналитик', 'pavel@sever.example',
        '$argon2id$v=19$m=65536,t=3,p=4$c2FsdHNhbHRzYWx0MDI$bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'analyst'),
    (3, 2, 'Ольга Южная', 'olga@yug.example',
        '$argon2id$v=19$m=65536,t=3,p=4$c2FsdHNhbHRzYWx0MDM$ccccccccccccccccccccccccccccccccccccccccccc',
        'organization_admin');

INSERT INTO invitation (invitation_id, organization_id, code, revoked) VALUES
    (1, 1, 'N0rthInviteCodeValue000000000001', false),
    (2, 1, 'N0rthInviteCodeValue000000000002', true);

INSERT INTO monitored_object (object_id, organization_id, name, object_type) VALUES
    (1, 1, 'Кроссовки', 'product'),
    (2, 2, 'Куртка', 'product');

INSERT INTO source (source_id, object_id, organization_id, platform_name, card_url) VALUES
    (1, 1, 1, 'Wildberries', 'https://shop.example/wb/krossovki'),
    (2, 1, 1, 'Ozon', 'https://shop.example/ozon/krossovki'),
    (3, 2, 2, 'Wildberries', 'https://shop.example/wb/kurtka');

INSERT INTO anomaly_threshold (organization_id, negativity_limit, spam_limit) VALUES
    (1, 2.00, 2.00),
    (2, 3.00, 3.00);

INSERT INTO import_batch (
    import_id, source_id, organization_id, status, accepted_count, undated_count,
    started_at, finished_at
) VALUES
    (1, 1, 1, 'ready', 8, 1, '2026-03-21 08:00:00+00', '2026-03-21 08:05:00+00'),
    (2, 2, 1, 'ready', 5, 0, '2026-03-21 08:10:00+00', '2026-03-21 08:14:00+00'),
    (3, 3, 2, 'ready', 1, 0, '2026-03-21 09:00:00+00', '2026-03-21 09:01:00+00');

INSERT INTO review (
    review_id, import_id, source_id, object_id, organization_id, body, reviewed_at, sentiment, spam
) VALUES
    (1,  1, 1, 1, 1, 'Зимняя покупка',            '2026-02-15 10:00:00+00', 'positive', false),
    (2,  1, 1, 1, 1, 'Отличные кроссовки',        '2026-03-06 10:00:00+00', 'positive', false),
    (3,  1, 1, 1, 1, 'Удобно ходить',             '2026-03-07 10:00:00+00', 'positive', false),
    (4,  1, 1, 1, 1, 'Обычные кроссовки',         '2026-03-08 10:00:00+00', 'neutral',  false),
    (5,  1, 1, 1, 1, 'Разошлись швы',             '2026-03-20 09:00:00+00', 'negative', true),
    (6,  1, 1, 1, 1, 'Разошлись швы',             '2026-03-20 10:00:00+00', 'negative', true),
    (7,  1, 1, 1, 1, 'Разошлись швы',             '2026-03-20 11:00:00+00', 'negative', true),
    (8,  1, 1, 1, 1, 'Пришло без даты',           NULL,                     'negative', NULL),
    (9,  2, 2, 1, 1, 'Хорошая пара',              '2026-03-10 10:00:00+00', 'positive', false),
    (10, 2, 2, 1, 1, 'Нормально',                 '2026-03-12 10:00:00+00', 'neutral',  false),
    (11, 2, 2, 1, 1, 'Разошлись швы',             '2026-03-20 12:00:00+00', 'negative', true),
    (12, 2, 2, 1, 1, 'Разошлись швы',             '2026-03-20 13:00:00+00', 'negative', true),
    (13, 2, 2, 1, 1, 'Порвались на второй день',  '2026-03-20 14:00:00+00', 'negative', false),
    (14, 3, 3, 2, 2, 'Тёплая куртка',             '2026-03-05 10:00:00+00', 'positive', false);

INSERT INTO anomaly (
    anomaly_id, object_id, organization_id, anomaly_type, status,
    window_start, window_end, baseline_start, baseline_end,
    window_total, window_marked, baseline_total, baseline_marked,
    window_rate, baseline_rate
) VALUES
    (1, 1, 1, 'negativity', 'open',
        '2026-03-20 00:00:00+00', '2026-03-21 00:00:00+00',
        '2026-03-06 00:00:00+00', '2026-03-20 00:00:00+00',
        6, 6, 5, 0, 1.000000, 0.000000),
    (2, 1, 1, 'spam', 'open',
        '2026-03-20 00:00:00+00', '2026-03-21 00:00:00+00',
        '2026-03-06 00:00:00+00', '2026-03-20 00:00:00+00',
        6, 5, 5, 0, 0.833333, 0.000000);

INSERT INTO anomaly_review (anomaly_id, review_id, organization_id, object_id) VALUES
    (1, 5, 1, 1),
    (1, 6, 1, 1),
    (1, 7, 1, 1),
    (1, 11, 1, 1),
    (1, 12, 1, 1),
    (1, 13, 1, 1),
    (2, 5, 1, 1),
    (2, 6, 1, 1),
    (2, 7, 1, 1),
    (2, 11, 1, 1),
    (2, 12, 1, 1);

INSERT INTO notification (notification_id, anomaly_id, organization_id, message) VALUES
    (1, 1, 1, 'Открыта аномалия негатива по объекту «Кроссовки»'),
    (2, 2, 1, 'Открыта аномалия спама по объекту «Кроссовки»');

SELECT setval(pg_get_serial_sequence('organization', 'organization_id'), (SELECT MAX(organization_id) FROM organization));
SELECT setval(pg_get_serial_sequence('account', 'account_id'), (SELECT MAX(account_id) FROM account));
SELECT setval(pg_get_serial_sequence('invitation', 'invitation_id'), (SELECT MAX(invitation_id) FROM invitation));
SELECT setval(pg_get_serial_sequence('monitored_object', 'object_id'), (SELECT MAX(object_id) FROM monitored_object));
SELECT setval(pg_get_serial_sequence('source', 'source_id'), (SELECT MAX(source_id) FROM source));
SELECT setval(pg_get_serial_sequence('import_batch', 'import_id'), (SELECT MAX(import_id) FROM import_batch));
SELECT setval(pg_get_serial_sequence('review', 'review_id'), (SELECT MAX(review_id) FROM review));
SELECT setval(pg_get_serial_sequence('anomaly', 'anomaly_id'), (SELECT MAX(anomaly_id) FROM anomaly));
SELECT setval(pg_get_serial_sequence('notification', 'notification_id'), (SELECT MAX(notification_id) FROM notification));
