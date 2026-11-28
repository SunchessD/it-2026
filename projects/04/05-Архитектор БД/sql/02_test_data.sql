-- Учебные данные для пустой схемы после 01_create_database.sql.
-- example.invalid и имена клубов обозначают вымышленные данные.
BEGIN;
SET LOCAL search_path = sygraem,public;

INSERT INTO account(email,role,adult_confirmed_at) VALUES
    ('maria@example.invalid','player',now()),
    ('alex@example.invalid','player',now()),
    ('elena@example.invalid','player',now()),
    ('admin@example.invalid','admin',NULL);

INSERT INTO player_profile(player_id,first_name,last_name,age_years,gender,city,ntrp) VALUES
    (1,'Мария','Иванова',28,'женский','Санкт-Петербург',3.5),
    (2,'Алексей','Крылов',31,'мужской','Санкт-Петербург',3.5),
    (3,'Елена','Петрова',29,'женский','Санкт-Петербург',4.0);
INSERT INTO player_contact VALUES (1,'maria_example'),(2,'alex_example'),(3,'elena_example');

INSERT INTO district(name) VALUES ('Петроградский'),('Приморский');
INSERT INTO metro_station(name) VALUES ('Петроградская'),('Комендантский проспект');
INSERT INTO tennis_center(district_id,name,address,website_url,hourly_price_rub,surfaces) VALUES
    (1,'Учебный клуб на Петроградской','Пример адреса 1','https://p.example.invalid',2000,ARRAY['хард']),
    (2,'Учебный клуб в Приморском','Пример адреса 2','https://k.example.invalid',1800,ARRAY['грунт']);
INSERT INTO center_metro VALUES (1,1),(2,2);

INSERT INTO game_request(author_id,publish_key,ntrp_min,ntrp_max,wishes,expires_at) VALUES
    (1,'10000000-0000-0000-0000-000000000001',3,4,'Одиночная игра',now()+interval '2 days'),
    (2,'10000000-0000-0000-0000-000000000002',3,4.5,NULL,now()+interval '2 days'),
    (3,'10000000-0000-0000-0000-000000000003',3.5,4.5,NULL,now()+interval '2 days'),
    (1,'10000000-0000-0000-0000-000000000004',3,4,NULL,now()+interval '2 days');

INSERT INTO request_window(request_id,time_slot)
SELECT request_id,tstzrange(
    (date_trunc('day',now() AT TIME ZONE 'Europe/Moscow')+interval '1 day'+start_offset)
        AT TIME ZONE 'Europe/Moscow',
    (date_trunc('day',now() AT TIME ZONE 'Europe/Moscow')+interval '1 day'+end_offset)
        AT TIME ZONE 'Europe/Moscow','[)')
FROM (VALUES (1,interval '18 hours',interval '20 hours'),
             (2,interval '18 hours 30 minutes',interval '19 hours 30 minutes'),
             (3,interval '18 hours',interval '20 hours'),
             (4,interval '20 hours',interval '21 hours')) AS seed(request_id,start_offset,end_offset);

INSERT INTO request_place(request_id,district_id,metro_id,center_id) VALUES
    (1,1,NULL,NULL),(2,NULL,1,NULL),(3,2,NULL,NULL),(4,NULL,NULL,1);
SELECT publish_request(1,1);
SELECT publish_request(2,2);
SELECT publish_request(3,3);
SELECT publish_request(1,4);

SELECT answer_offer(1,send_offer(2,1,'20000000-0000-0000-0000-000000000001','Могу с 18:30.',2),true);
SELECT propose_time(2,1,lower(time_slot)) FROM request_window WHERE request_id=2;
SELECT confirm_time(1,1,1);

-- Второе предложение оставлено без ответа.
SELECT send_offer(3,2,'20000000-0000-0000-0000-000000000002','Уточним место после согласия.');

INSERT INTO report(reporter_id,request_id,reason,status,assigned_admin_id)
VALUES (3,4,'Учебная жалоба на описание', 'reviewing',4);
COMMIT;
