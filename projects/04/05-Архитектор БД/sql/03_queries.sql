-- Выполнить после 01 и 02. PREPARE действует в текущем соединении.
-- В параметр игрока сервер подставляет идентификатор из проверенного сеанса.
SET search_path = sygraem,public;

-- Публичная карточка. Пустой результат означает недоступную заявку.
PREPARE public_card(uuid,bigint) AS
SELECT r.public_key,p.first_name,left(p.last_name,1) AS last_initial,p.ntrp,
       r.ntrp_min,r.ntrp_max,r.wishes,
       (SELECT array_agg(time_slot ORDER BY lower(time_slot))
        FROM request_window WHERE request_id=r.request_id AND upper(time_slot)>statement_timestamp()) AS windows,
       (SELECT array_agg(coalesce(d.name,m.name,c.name) ORDER BY rp.place_id)
        FROM request_place rp LEFT JOIN district d USING (district_id)
        LEFT JOIN metro_station m USING (metro_id) LEFT JOIN tennis_center c USING (center_id)
        WHERE rp.request_id=r.request_id) AS allowed_places
FROM active_request r JOIN player_profile p ON p.player_id=r.author_id
WHERE r.public_key=$1 AND ($2 IS NULL OR NOT pair_is_blocked($2,r.author_id));

-- Лента доступна без своей заявки. Фильтр по времени, центру и уровню автора.
PREPARE feed(bigint,tstzrange,bigint,numeric,numeric,integer,integer) AS
SELECT r.request_id,r.public_key,p.first_name,left(p.last_name,1) AS last_initial,p.ntrp,r.published_at
FROM active_request r JOIN player_profile p ON p.player_id=r.author_id
WHERE r.author_id<>$1 AND NOT pair_is_blocked($1,r.author_id)
  AND ($2 IS NULL OR EXISTS (SELECT 1 FROM request_window w WHERE w.request_id=r.request_id
                            AND upper(w.time_slot)>statement_timestamp() AND w.time_slot && $2))
  AND ($3 IS NULL OR EXISTS (SELECT 1 FROM request_center c WHERE c.request_id=r.request_id AND c.center_id=$3))
  AND ($4 IS NULL OR p.ntrp>=$4) AND ($5 IS NULL OR p.ntrp<=$5)
ORDER BY r.published_at DESC,r.request_id DESC
LIMIT greatest(1,least(coalesce($6,20),20)) OFFSET greatest(0,coalesce($7,0));

-- Совпадения с объяснением. Один результат на чужую заявку.
PREPARE matches(bigint,bigint) AS
WITH mine AS (
    SELECT r.*,p.ntrp FROM active_request r JOIN player_profile p ON p.player_id=r.author_id
    WHERE r.request_id=$2 AND r.author_id=$1
), candidates AS (
    SELECT other.request_id,other.author_id,other.ntrp_min,other.ntrp_max,
           p.first_name,left(p.last_name,1) AS last_initial,p.ntrp,mine.request_id AS my_request
    FROM mine JOIN active_request other ON other.author_id<>mine.author_id
    JOIN player_profile p ON p.player_id=other.author_id
    WHERE p.ntrp BETWEEN mine.ntrp_min AND mine.ntrp_max
      AND mine.ntrp BETWEEN other.ntrp_min AND other.ntrp_max
      AND NOT pair_is_blocked(mine.author_id,other.author_id)
)
SELECT q.request_id,q.first_name,q.last_initial,q.ntrp,
       span.from_at AS common_from,span.to_at AS common_to,club.center_id,club.name AS common_center
FROM candidates q
JOIN LATERAL (
    SELECT a.center_id,c.name
    FROM request_center a JOIN request_center b USING (center_id)
    JOIN tennis_center c USING (center_id)
    WHERE a.request_id=q.my_request AND b.request_id=q.request_id
    ORDER BY a.center_id LIMIT 1
) club ON true
JOIN LATERAL (
    SELECT greatest(lower(slot),statement_timestamp()) AS from_at,upper(slot) AS to_at
    FROM (
        SELECT range_agg(a.time_slot * b.time_slot) AS combined
        FROM request_window a JOIN request_window b ON a.time_slot && b.time_slot
        WHERE a.request_id=q.my_request AND b.request_id=q.request_id
    ) window_union CROSS JOIN LATERAL unnest(window_union.combined) slots(slot)
    WHERE upper(slot)-greatest(lower(slot),statement_timestamp()) >= interval '60 minutes'
    ORDER BY upper(slot)-greatest(lower(slot),statement_timestamp()) DESC,from_at LIMIT 1
) span ON true
ORDER BY span.to_at-span.from_at DESC,span.from_at,q.request_id
LIMIT 20;

PREPARE my_requests(bigint) AS
SELECT r.request_id,r.public_key,
       CASE WHEN r.status='active' AND ar.request_id IS NULL
            AND (r.expires_at<=statement_timestamp() OR NOT EXISTS (
              SELECT 1 FROM request_window w WHERE w.request_id=r.request_id
              AND upper(w.time_slot)>statement_timestamp()))
            THEN 'expired' ELSE r.status END AS status,
       r.published_at,r.expires_at
FROM game_request r LEFT JOIN active_request ar USING (request_id)
WHERE r.author_id=$1
ORDER BY r.created_at DESC,r.request_id DESC;

PREPARE inbox(bigint) AS
SELECT o.offer_id,o.target_request_id,o.sender_id,
       CASE WHEN o.status='pending' AND (r.request_id IS NULL OR sender.status<>'active'
         OR pair_is_blocked(o.sender_id,o.recipient_id)) THEN 'unavailable' ELSE o.status END AS status,
       o.message,o.created_at
FROM offer o JOIN account sender ON sender.account_id=o.sender_id
LEFT JOIN active_request r ON r.request_id=o.target_request_id
WHERE o.recipient_id=$1 ORDER BY o.created_at DESC,o.offer_id DESC;

-- Контакт выдаётся только другому участнику состоявшейся договорённости.
PREPARE partner_contact(bigint,bigint) AS
SELECT a.agreement_id,p.first_name,left(p.last_name,1) AS last_initial,c.telegram_username
FROM agreement a JOIN agreement_member own ON own.agreement_id=a.agreement_id AND own.player_id=$1
JOIN agreement_member other ON other.agreement_id=a.agreement_id AND other.player_id<>$1
JOIN player_profile p ON p.player_id=other.player_id
LEFT JOIN player_contact c ON c.player_id=p.player_id
WHERE a.agreement_id=$2;

PREPARE player_game_count(bigint) AS
SELECT count(*) AS confirmed_games
FROM agreement_member m JOIN agreement_result r USING (agreement_id)
WHERE m.player_id=$1 AND r.outcome='confirmed_play';

PREPARE notifications_for_player(bigint) AS
SELECT n.notification_id,n.kind,n.offer_id,n.agreement_id,n.due_at,n.shown_at
FROM notification n WHERE n.recipient_id=$1 AND n.canceled_at IS NULL AND n.due_at<=statement_timestamp()
ORDER BY n.due_at DESC,n.notification_id DESC LIMIT 20;

PREPARE center_catalog(bigint,integer) AS
SELECT center_id,name,address,phone,website_url,hourly_price_rub,surfaces,updated_at
FROM tennis_center WHERE ($1 IS NULL OR district_id=$1)
ORDER BY name,center_id LIMIT 20 OFFSET greatest(0,coalesce($2,0));

PREPARE moderation_queue(bigint) AS
SELECT r.* FROM report r
WHERE r.status IN ('new','reviewing') AND EXISTS (
    SELECT 1 FROM account a WHERE a.account_id=$1 AND a.role='admin' AND a.status='active'
)
ORDER BY r.created_at,r.report_id LIMIT 20;

-- Свернуть реальные истечения в статус и записать событие один раз.
PREPARE expire_requests AS
WITH expired AS (
    UPDATE game_request r SET status='expired'
    WHERE r.status='active' AND (
       r.expires_at<=statement_timestamp() OR NOT EXISTS (
           SELECT 1 FROM request_window w WHERE w.request_id=r.request_id
              AND upper(w.time_slot)>statement_timestamp()))
    RETURNING request_id
)
INSERT INTO product_event(kind,request_id) SELECT 'request_expired',request_id FROM expired;

PREPARE close_request(bigint,bigint) AS
UPDATE game_request SET status='closed'
WHERE author_id=$1 AND request_id=$2 AND status='active';

PREPARE send_proposal(bigint,bigint,uuid,text,bigint,text) AS
SELECT send_offer($1,$2,$3,$4,$5,$6);

PREPARE respond_to_proposal(bigint,bigint,boolean) AS
SELECT answer_offer($1,$2,$3);

PREPARE set_meeting_time(bigint,bigint,timestamptz) AS
SELECT propose_time($1,$2,$3);

PREPARE confirm_meeting_time(bigint,bigint,integer) AS
SELECT confirm_time($1,$2,$3);

PREPARE cancel_meeting(bigint,bigint) AS
SELECT cancel_agreement($1,$2);

PREPARE submit_feedback(bigint,bigint,boolean,smallint,boolean,text) AS
SELECT save_feedback($1,$2,$3,$4,$5,$6);

-- Зрелая когорта по дате публикации. Результат относится к целевой заявке предложения.
PREPARE pilot_conversion(timestamptz,timestamptz) AS
WITH cohort AS (
    SELECT request_id,published_at,published_at+interval '720 hours' AS deadline
    FROM game_request
    WHERE published_at >= $1 AND published_at < $2
      AND published_at+interval '720 hours' <= statement_timestamp()
), per_request AS (
    SELECT c.request_id,c.published_at,min(o.answered_at) AS first_agreement_at,
           coalesce(bool_or(f.yes_count=2),false) AS confirmed_play
    FROM cohort c LEFT JOIN offer o ON o.target_request_id=c.request_id AND o.status='accepted'
           AND o.answered_at>=c.published_at AND o.answered_at<c.deadline
    LEFT JOIN agreement a ON a.offer_id=o.offer_id
    LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE played) AS yes_count FROM feedback f
        WHERE f.agreement_id=a.agreement_id AND f.created_at<c.deadline
    ) f ON true
    GROUP BY c.request_id,c.published_at
)
SELECT count(*) AS requests,count(first_agreement_at) AS with_agreement,
       count(*) FILTER (WHERE confirmed_play) AS with_confirmed_game,
       avg(first_agreement_at-published_at) AS mean_time_to_agreement
FROM per_request;

-- Повторная игра: последующая подтверждённая встреча той же пары.
PREPARE repeated_games AS
WITH games AS (
    SELECT a.agreement_id,least(a.sender_id,a.recipient_id) AS first_player,
           greatest(a.sender_id,a.recipient_id) AS second_player,m.starts_at
    FROM agreement a JOIN agreement_result r USING (agreement_id)
    JOIN meeting_time m USING (agreement_id)
    WHERE r.outcome='confirmed_play'
), numbered AS (
    SELECT *,row_number() OVER (PARTITION BY first_player,second_player
           ORDER BY starts_at,agreement_id) AS meeting_number
    FROM games
)
SELECT agreement_id,first_player,second_player,starts_at FROM numbered
WHERE meeting_number>1 ORDER BY starts_at,agreement_id;

-- Демонстрация чтения на данных из 02_test_data.sql.
EXECUTE feed(1,NULL,NULL,NULL,NULL,20,0);
EXECUTE matches(1,1);
EXECUTE inbox(2);
EXECUTE partner_contact(1,1);
EXECUTE notifications_for_player(1);
EXECUTE center_catalog(NULL,0);
EXECUTE moderation_queue(4);
RESET search_path;
