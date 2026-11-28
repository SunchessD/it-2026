-- «Сыграем». Выполнить в пустой БД PostgreSQL.
-- Для установки btree_gist нужны права на создание расширения.
BEGIN;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA sygraem;
SET LOCAL search_path = sygraem, public;

-- Учётные записи и профиль
CREATE TABLE account (
    account_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email text NOT NULL CHECK (email = lower(btrim(email)) AND position('@' IN email) > 1),
    role text NOT NULL DEFAULT 'player' CHECK (role IN ('player','admin')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked')),
    adult_confirmed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (email),
    CHECK (role <> 'player' OR adult_confirmed_at IS NOT NULL)
);

CREATE TABLE player_profile (
    player_id bigint PRIMARY KEY REFERENCES account,
    first_name text NOT NULL CHECK (btrim(first_name) <> ''),
    last_name text NOT NULL CHECK (btrim(last_name) <> ''),
    age_years smallint NOT NULL CHECK (age_years >= 18),
    gender text NOT NULL CHECK (btrim(gender) <> ''),
    city text NOT NULL CHECK (btrim(city) <> ''),
    ntrp numeric(2,1) NOT NULL CHECK (ntrp BETWEEN 1 AND 7 AND mod(ntrp,0.5)=0),
    photo_url text,
    about text,
    experience text
);

CREATE TABLE player_contact (
    player_id bigint PRIMARY KEY REFERENCES player_profile,
    telegram_username text NOT NULL CHECK (telegram_username ~ '^[A-Za-z0-9_]+$')
);

CREATE TABLE login_challenge (
    challenge_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id bigint NOT NULL REFERENCES account,
    kind text NOT NULL CHECK (kind IN ('code','link')),
    secret_digest bytea NOT NULL CHECK (octet_length(secret_digest) >= 32),
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    failed_attempts smallint NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
    CHECK (expires_at > issued_at AND expires_at <= issued_at +
        CASE kind WHEN 'code' THEN interval '10 minutes' ELSE interval '15 minutes' END),
    CHECK (used_at IS NULL OR (used_at >= issued_at AND used_at < expires_at))
);
CREATE INDEX login_challenge_account_idx ON login_challenge (account_id, expires_at DESC);

-- Каталог и география
CREATE TABLE district (
    district_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE
);
CREATE TABLE metro_station (
    metro_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE
);
CREATE TABLE tennis_center (
    center_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    district_id bigint NOT NULL REFERENCES district,
    name text NOT NULL,
    address text NOT NULL,
    phone text,
    website_url text,
    hourly_price_rub numeric(9,2) CHECK (hourly_price_rub >= 0),
    surfaces text[] NOT NULL DEFAULT '{}',
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (name,address)
);
CREATE INDEX tennis_center_district_idx ON tennis_center (district_id);
CREATE TABLE center_metro (
    center_id bigint REFERENCES tennis_center,
    metro_id bigint REFERENCES metro_station,
    PRIMARY KEY (center_id,metro_id)
);
CREATE INDEX center_metro_station_idx ON center_metro (metro_id,center_id);

-- Заявки и варианты условий
CREATE TABLE game_request (
    request_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_id bigint NOT NULL REFERENCES player_profile,
    publish_key uuid NOT NULL,
    public_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    ntrp_min numeric(2,1) NOT NULL CHECK (ntrp_min BETWEEN 1 AND 7 AND mod(ntrp_min,0.5)=0),
    ntrp_max numeric(2,1) NOT NULL CHECK (ntrp_max BETWEEN 1 AND 7 AND mod(ntrp_max,0.5)=0),
    wishes text,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','closed','expired','hidden')),
    created_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    expires_at timestamptz NOT NULL,
    UNIQUE (author_id,publish_key),
    UNIQUE (request_id,author_id),
    CHECK (ntrp_min <= ntrp_max),
    CHECK (expires_at > created_at),
    CHECK (status NOT IN ('active','expired') OR published_at IS NOT NULL),
    CHECK (published_at IS NULL OR published_at < expires_at)
);
CREATE INDEX game_request_feed_idx ON game_request (published_at DESC,request_id DESC)
    WHERE status='active';

CREATE TABLE request_window (
    window_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id bigint NOT NULL REFERENCES game_request,
    time_slot tstzrange NOT NULL,
    UNIQUE (request_id,time_slot),
    CHECK (NOT isempty(time_slot) AND NOT lower_inf(time_slot) AND NOT upper_inf(time_slot)
        AND lower_inc(time_slot) AND NOT upper_inc(time_slot)
        AND upper(time_slot)-lower(time_slot) >= interval '60 minutes')
);
CREATE INDEX request_window_slot_idx ON request_window USING gist (time_slot);

CREATE TABLE request_place (
    place_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id bigint NOT NULL REFERENCES game_request,
    district_id bigint REFERENCES district,
    metro_id bigint REFERENCES metro_station,
    center_id bigint REFERENCES tennis_center,
    CHECK (num_nonnulls(district_id,metro_id,center_id)=1),
    UNIQUE NULLS NOT DISTINCT (request_id,district_id,metro_id,center_id)
);

CREATE VIEW request_center AS
    SELECT rp.request_id,c.center_id
    FROM request_place rp JOIN tennis_center c ON c.district_id=rp.district_id
    UNION
    SELECT rp.request_id,cm.center_id
    FROM request_place rp JOIN center_metro cm ON cm.metro_id=rp.metro_id
    UNION
    SELECT request_id,center_id FROM request_place WHERE center_id IS NOT NULL;

CREATE VIEW active_request AS
    SELECT r.*
    FROM game_request r JOIN account a ON a.account_id=r.author_id
    WHERE r.status='active' AND a.status='active' AND r.expires_at > statement_timestamp()
      AND EXISTS (SELECT 1 FROM request_window w WHERE w.request_id=r.request_id
                  AND upper(w.time_slot)>statement_timestamp());

-- Предложения и договорённости
CREATE TABLE player_block (
    blocker_id bigint REFERENCES player_profile,
    blocked_id bigint REFERENCES player_profile,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id,blocked_id),
    CHECK (blocker_id<>blocked_id)
);

CREATE TABLE offer (
    offer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_request_id bigint NOT NULL,
    recipient_id bigint NOT NULL,
    sender_id bigint NOT NULL REFERENCES player_profile,
    counter_request_id bigint,
    send_key uuid NOT NULL,
    message text CHECK (length(message)<=500),
    response_terms text,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
    created_at timestamptz NOT NULL DEFAULT now(),
    answered_at timestamptz,
    FOREIGN KEY (target_request_id,recipient_id) REFERENCES game_request (request_id,author_id),
    FOREIGN KEY (counter_request_id,sender_id) REFERENCES game_request (request_id,author_id),
    UNIQUE (sender_id,send_key),
    UNIQUE (offer_id,sender_id,recipient_id),
    CHECK (sender_id<>recipient_id),
    CHECK ((status='pending')=(answered_at IS NULL))
);
CREATE UNIQUE INDEX offer_pending_pair_idx ON offer (target_request_id,sender_id) WHERE status='pending';
CREATE INDEX offer_inbox_idx ON offer (recipient_id,created_at DESC);
CREATE INDEX offer_sender_time_idx ON offer (sender_id,created_at DESC);

CREATE TABLE agreement (
    agreement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    offer_id bigint NOT NULL UNIQUE,
    sender_id bigint NOT NULL,
    recipient_id bigint NOT NULL,
    center_id bigint REFERENCES tennis_center,
    created_at timestamptz NOT NULL DEFAULT now(),
    canceled_at timestamptz,
    canceled_by bigint REFERENCES player_profile,
    FOREIGN KEY (offer_id,sender_id,recipient_id) REFERENCES offer (offer_id,sender_id,recipient_id),
    CHECK ((canceled_at IS NULL)=(canceled_by IS NULL)),
    CHECK (canceled_by IS NULL OR canceled_by IN (sender_id,recipient_id))
);

CREATE TABLE agreement_member (
    agreement_id bigint REFERENCES agreement,
    player_id bigint REFERENCES player_profile,
    confirmed_slot tstzrange,
    PRIMARY KEY (agreement_id,player_id),
    CONSTRAINT member_no_time_overlap EXCLUDE USING gist (player_id WITH =, confirmed_slot WITH &&)
        WHERE (confirmed_slot IS NOT NULL),
    CHECK (confirmed_slot IS NULL OR (NOT isempty(confirmed_slot)
        AND lower(confirmed_slot) IS NOT NULL AND upper(confirmed_slot) IS NOT NULL
        AND lower_inc(confirmed_slot) AND NOT upper_inc(confirmed_slot)
        AND upper(confirmed_slot)-lower(confirmed_slot)=interval '60 minutes'))
);

CREATE TABLE meeting_time (
    agreement_id bigint PRIMARY KEY REFERENCES agreement,
    version integer NOT NULL DEFAULT 1 CHECK (version>0),
    proposed_by bigint NOT NULL,
    starts_at timestamptz NOT NULL,
    confirmed_by bigint,
    confirmed_at timestamptz,
    FOREIGN KEY (agreement_id,proposed_by) REFERENCES agreement_member,
    FOREIGN KEY (agreement_id,confirmed_by) REFERENCES agreement_member,
    CHECK (confirmed_by IS NULL OR confirmed_by<>proposed_by),
    CHECK ((confirmed_at IS NULL)=(confirmed_by IS NULL))
);

CREATE TABLE feedback (
    agreement_id bigint,
    player_id bigint,
    played boolean NOT NULL,
    ntrp_fit smallint CHECK (ntrp_fit BETWEEN -2 AND 2),
    play_again boolean,
    no_game_reason text CHECK (no_game_reason IN ('early_cancel','late_cancel','no_show','other')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (agreement_id,player_id),
    FOREIGN KEY (agreement_id,player_id) REFERENCES agreement_member,
    CHECK ((played AND ntrp_fit IS NOT NULL AND play_again IS NOT NULL AND no_game_reason IS NULL)
        OR (NOT played AND ntrp_fit IS NULL AND play_again IS NULL AND no_game_reason IS NOT NULL))
);
CREATE VIEW agreement_result AS
    SELECT a.agreement_id, CASE
        WHEN count(*) FILTER (WHERE f.played)=2 THEN 'confirmed_play'
        WHEN count(*) FILTER (WHERE NOT f.played)=2 THEN 'not_played'
        ELSE 'unconfirmed' END AS outcome
    FROM agreement a LEFT JOIN feedback f USING (agreement_id)
    GROUP BY a.agreement_id;

-- Уведомления, жалобы и продуктовые события
CREATE TABLE notification (
    notification_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recipient_id bigint NOT NULL REFERENCES player_profile,
    event_key text NOT NULL UNIQUE,
    kind text NOT NULL CHECK (kind IN ('offer_new','offer_accepted','meeting_canceled','reminder','feedback_due')),
    offer_id bigint REFERENCES offer,
    agreement_id bigint REFERENCES agreement,
    due_at timestamptz NOT NULL,
    shown_at timestamptz,
    canceled_at timestamptz,
    CHECK (num_nonnulls(offer_id,agreement_id)=1),
    CHECK ((kind='offer_new' AND offer_id IS NOT NULL) OR (kind<>'offer_new' AND agreement_id IS NOT NULL))
);
CREATE INDEX notification_due_idx ON notification (recipient_id,due_at) WHERE canceled_at IS NULL;

CREATE TABLE report (
    report_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reporter_id bigint NOT NULL REFERENCES player_profile,
    reported_account_id bigint REFERENCES account,
    request_id bigint REFERENCES game_request,
    offer_id bigint REFERENCES offer,
    reason text NOT NULL CHECK (btrim(reason)<>''),
    status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','reviewing','resolved','dismissed')),
    assigned_admin_id bigint REFERENCES account,
    created_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    CHECK (num_nonnulls(reported_account_id,request_id,offer_id)=1)
);
CREATE INDEX report_queue_idx ON report (status,created_at);

CREATE TABLE product_event (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_key uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    kind text NOT NULL CHECK (kind IN ('registered','request_published','request_expired','matches_viewed',
        'offer_sent','offer_accepted','offer_declined','center_selected','center_link_opened',
        'meeting_canceled','feedback_saved')),
    actor_id bigint REFERENCES account,
    request_id bigint REFERENCES game_request,
    offer_id bigint REFERENCES offer,
    agreement_id bigint REFERENCES agreement,
    center_id bigint REFERENCES tennis_center,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_event_kind_time_idx ON product_event (kind,occurred_at);

-- Запись через эти операции выполняет сервер. Идентификатор игрока берётся из сеанса.
CREATE FUNCTION use_login_challenge(p_challenge uuid,p_digest bytea) RETURNS bigint
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE c login_challenge%ROWTYPE;
BEGIN
    SELECT * INTO c FROM login_challenge WHERE challenge_id=p_challenge FOR UPDATE;
    IF NOT FOUND OR c.used_at IS NOT NULL OR c.expires_at<=statement_timestamp()
       OR c.failed_attempts>=5 OR p_digest IS NULL
       OR NOT EXISTS (SELECT 1 FROM account WHERE account_id=c.account_id AND status='active')
    THEN RETURN NULL; END IF;
    IF c.secret_digest<>p_digest THEN
        UPDATE login_challenge SET failed_attempts=failed_attempts+1 WHERE challenge_id=p_challenge;
        RETURN NULL;
    END IF;
    UPDATE login_challenge SET used_at=statement_timestamp() WHERE challenge_id=p_challenge;
    RETURN c.account_id;
END
$$;

CREATE FUNCTION pair_is_blocked(a bigint,b bigint) RETURNS boolean
LANGUAGE sql STABLE SET search_path = sygraem,public AS $$
    SELECT EXISTS (SELECT 1 FROM player_block
                   WHERE (blocker_id=a AND blocked_id=b) OR (blocker_id=b AND blocked_id=a))
$$;

CREATE FUNCTION publish_request(p_author bigint,p_request bigint) RETURNS void
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE r game_request%ROWTYPE;
BEGIN
    SELECT * INTO STRICT r FROM game_request WHERE request_id=p_request AND author_id=p_author FOR UPDATE;
    IF r.status='active' THEN RETURN; END IF;
    IF r.status<>'draft' OR r.expires_at<=statement_timestamp()
       OR NOT EXISTS (SELECT 1 FROM account WHERE account_id=p_author AND status='active' AND role='player')
       OR NOT EXISTS (SELECT 1 FROM request_window WHERE request_id=p_request)
       OR EXISTS (SELECT 1 FROM request_window WHERE request_id=p_request AND lower(time_slot)<=statement_timestamp())
       OR NOT EXISTS (SELECT 1 FROM request_place WHERE request_id=p_request) THEN
        RAISE EXCEPTION 'Заявку нельзя опубликовать';
    END IF;
    UPDATE game_request SET status='active',published_at=statement_timestamp() WHERE request_id=p_request;
    INSERT INTO product_event(kind,actor_id,request_id) VALUES ('request_published',p_author,p_request);
END
$$;

CREATE FUNCTION send_offer(p_sender bigint,p_request bigint,p_key uuid,p_message text,
    p_counter bigint DEFAULT NULL,p_terms text DEFAULT NULL) RETURNS bigint
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE r game_request%ROWTYPE; existing offer%ROWTYPE; result_id bigint;
BEGIN
    PERFORM 1 FROM account WHERE account_id=p_sender AND status='active' AND role='player' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Игрок недоступен'; END IF;
    SELECT * INTO existing FROM offer WHERE sender_id=p_sender AND send_key=p_key;
    IF FOUND THEN
        IF existing.target_request_id<>p_request OR existing.counter_request_id IS DISTINCT FROM p_counter
           OR existing.message IS DISTINCT FROM p_message OR existing.response_terms IS DISTINCT FROM p_terms THEN
            RAISE EXCEPTION 'Ключ запроса уже использован с другими условиями';
        END IF;
        RETURN existing.offer_id;
    END IF;
    IF (SELECT count(*) FROM offer WHERE sender_id=p_sender
        AND created_at>statement_timestamp()-interval '1 minute')>=20 THEN
        RAISE EXCEPTION 'Лимит отправки предложений';
    END IF;
    PERFORM 1 FROM game_request WHERE request_id=p_request FOR UPDATE;
    SELECT * INTO r FROM active_request WHERE request_id=p_request;
    IF NOT FOUND OR r.author_id=p_sender OR pair_is_blocked(p_sender,r.author_id) THEN
        RAISE EXCEPTION 'Отклик недоступен';
    END IF;
    IF p_counter IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM active_request WHERE request_id=p_counter AND author_id=p_sender) THEN
        RAISE EXCEPTION 'Встречная заявка недоступна';
    END IF;
    INSERT INTO offer(target_request_id,recipient_id,sender_id,send_key,message,counter_request_id,response_terms)
    VALUES (p_request,r.author_id,p_sender,p_key,p_message,p_counter,p_terms)
    RETURNING offer_id INTO result_id;
    INSERT INTO notification(recipient_id,event_key,kind,offer_id,due_at)
    VALUES (r.author_id,'offer:'||result_id,'offer_new',result_id,statement_timestamp());
    INSERT INTO product_event(kind,actor_id,request_id,offer_id) VALUES ('offer_sent',p_sender,p_request,result_id);
    RETURN result_id;
END
$$;

CREATE FUNCTION answer_offer(p_actor bigint,p_offer bigint,p_accept boolean) RETURNS bigint
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE o offer%ROWTYPE; result_id bigint;
BEGIN
    IF p_accept IS NULL THEN RAISE EXCEPTION 'Нужен ответ'; END IF;
    SELECT * INTO STRICT o FROM offer WHERE offer_id=p_offer AND recipient_id=p_actor FOR UPDATE;
    IF o.status='accepted' AND p_accept THEN
        SELECT agreement_id INTO STRICT result_id FROM agreement WHERE offer_id=p_offer;
        RETURN result_id;
    END IF;
    IF o.status='declined' AND NOT p_accept THEN RETURN NULL; END IF;
    PERFORM 1 FROM game_request WHERE request_id=o.target_request_id FOR UPDATE;
    IF o.status<>'pending' OR NOT EXISTS (SELECT 1 FROM active_request WHERE request_id=o.target_request_id)
       OR NOT EXISTS (SELECT 1 FROM account WHERE account_id=o.sender_id AND status='active')
       OR pair_is_blocked(o.sender_id,o.recipient_id) THEN
        RAISE EXCEPTION 'Ответ по предложению недоступен';
    END IF;
    UPDATE offer SET status=CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        answered_at=statement_timestamp() WHERE offer_id=p_offer;
    IF p_accept THEN
        INSERT INTO agreement(offer_id,sender_id,recipient_id) VALUES (p_offer,o.sender_id,o.recipient_id)
        RETURNING agreement_id INTO result_id;
        INSERT INTO agreement_member(agreement_id,player_id) VALUES (result_id,o.sender_id),(result_id,o.recipient_id);
        INSERT INTO notification(recipient_id,event_key,kind,agreement_id,due_at)
        VALUES (o.sender_id,'accepted:'||p_offer,'offer_accepted',result_id,statement_timestamp());
    END IF;
    INSERT INTO product_event(kind,actor_id,request_id,offer_id,agreement_id)
    VALUES (CASE WHEN p_accept THEN 'offer_accepted' ELSE 'offer_declined' END,
        p_actor,o.target_request_id,p_offer,result_id);
    RETURN result_id;
END
$$;

CREATE FUNCTION propose_time(p_actor bigint,p_agreement bigint,p_start timestamptz) RETURNS integer
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE result_version integer;
BEGIN
    PERFORM 1 FROM agreement WHERE agreement_id=p_agreement AND canceled_at IS NULL
        AND p_actor IN (sender_id,recipient_id) FOR UPDATE;
    IF NOT FOUND OR p_start IS NULL OR p_start<=statement_timestamp() THEN
        RAISE EXCEPTION 'Невозможно предложить время';
    END IF;
    UPDATE agreement_member SET confirmed_slot=NULL WHERE agreement_id=p_agreement AND confirmed_slot IS NOT NULL;
    UPDATE notification SET canceled_at=statement_timestamp()
    WHERE agreement_id=p_agreement AND kind IN ('reminder','feedback_due') AND shown_at IS NULL AND canceled_at IS NULL;
    INSERT INTO meeting_time(agreement_id,proposed_by,starts_at) VALUES (p_agreement,p_actor,p_start)
    ON CONFLICT (agreement_id) DO UPDATE SET proposed_by=excluded.proposed_by,
        starts_at=excluded.starts_at,version=meeting_time.version+1,confirmed_by=NULL,confirmed_at=NULL
    RETURNING version INTO result_version;
    RETURN result_version;
END
$$;

CREATE FUNCTION confirm_time(p_actor bigint,p_agreement bigint,p_version integer) RETURNS void
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE m meeting_time%ROWTYPE;
BEGIN
    PERFORM 1 FROM agreement WHERE agreement_id=p_agreement AND canceled_at IS NULL
        AND p_actor IN (sender_id,recipient_id) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Встреча недоступна'; END IF;
    SELECT * INTO STRICT m FROM meeting_time WHERE agreement_id=p_agreement AND version=p_version;
    IF m.confirmed_by=p_actor THEN RETURN; END IF;
    IF m.proposed_by=p_actor OR m.confirmed_at IS NOT NULL OR m.starts_at<=statement_timestamp() THEN
        RAISE EXCEPTION 'Подтверждение недоступно';
    END IF;
    -- Ограничение EXCLUDE проверяет оба интервала и действует при параллельных подтверждениях.
    UPDATE agreement_member SET confirmed_slot=tstzrange(m.starts_at,m.starts_at+interval '1 hour','[)')
    WHERE agreement_id=p_agreement;
    UPDATE meeting_time SET confirmed_by=p_actor,confirmed_at=statement_timestamp() WHERE agreement_id=p_agreement;
    INSERT INTO notification(recipient_id,event_key,kind,agreement_id,due_at)
    SELECT player_id,p_agreement||':'||m.version||':'||player_id||':'||job.kind,job.kind,p_agreement,job.due_at
    FROM agreement_member CROSS JOIN LATERAL
        (VALUES ('reminder',m.starts_at-interval '2 hours'),('feedback_due',m.starts_at+interval '1 hour')) job(kind,due_at)
    WHERE agreement_id=p_agreement AND job.due_at>=statement_timestamp();
END
$$;

CREATE FUNCTION cancel_agreement(p_actor bigint,p_agreement bigint) RETURNS void
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
DECLARE a agreement%ROWTYPE;
BEGIN
    SELECT * INTO STRICT a FROM agreement WHERE agreement_id=p_agreement
        AND p_actor IN (sender_id,recipient_id) FOR UPDATE;
    IF a.canceled_at IS NOT NULL THEN RETURN; END IF;
    UPDATE agreement SET canceled_by=p_actor,canceled_at=statement_timestamp() WHERE agreement_id=p_agreement;
    UPDATE agreement_member SET confirmed_slot=NULL WHERE agreement_id=p_agreement AND confirmed_slot IS NOT NULL;
    UPDATE notification SET canceled_at=statement_timestamp()
    WHERE agreement_id=p_agreement AND kind IN ('reminder','feedback_due') AND shown_at IS NULL AND canceled_at IS NULL;
    INSERT INTO notification(recipient_id,event_key,kind,agreement_id,due_at)
    VALUES (CASE WHEN p_actor=a.sender_id THEN a.recipient_id ELSE a.sender_id END,
        'cancel:'||p_agreement,'meeting_canceled',p_agreement,statement_timestamp());
    INSERT INTO product_event(kind,actor_id,agreement_id) VALUES ('meeting_canceled',p_actor,p_agreement);
END
$$;

CREATE FUNCTION save_feedback(p_actor bigint,p_agreement bigint,p_played boolean,
    p_ntrp smallint,p_again boolean,p_reason text) RETURNS void
LANGUAGE plpgsql SET search_path = sygraem,public AS $$
BEGIN
    PERFORM 1 FROM agreement WHERE agreement_id=p_agreement AND canceled_at IS NULL
        AND p_actor IN (sender_id,recipient_id) FOR UPDATE;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM meeting_time WHERE agreement_id=p_agreement
        AND confirmed_at IS NOT NULL AND starts_at+interval '1 hour'<=statement_timestamp()) THEN
        RAISE EXCEPTION 'Ответ об игре пока недоступен';
    END IF;
    INSERT INTO feedback(agreement_id,player_id,played,ntrp_fit,play_again,no_game_reason)
    VALUES (p_agreement,p_actor,p_played,p_ntrp,p_again,p_reason)
    ON CONFLICT (agreement_id,player_id) DO NOTHING;
    IF NOT FOUND THEN
        IF NOT EXISTS (SELECT 1 FROM feedback WHERE agreement_id=p_agreement AND player_id=p_actor
           AND ROW(played,ntrp_fit,play_again,no_game_reason) IS NOT DISTINCT FROM ROW(p_played,p_ntrp,p_again,p_reason)) THEN
            RAISE EXCEPTION 'Ответ об игре уже сохранён';
        END IF;
        RETURN;
    END IF;
    INSERT INTO product_event(kind,actor_id,agreement_id) VALUES ('feedback_saved',p_actor,p_agreement);
END
$$;
COMMIT;
