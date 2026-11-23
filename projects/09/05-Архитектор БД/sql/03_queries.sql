-- Запросы ReviewGuard к контрольному набору.
-- Период марта задан полуинтервалом [2026-03-01, 2026-04-01).
-- В приложении литералы заменяются параметрами драйвера, текст SQL не склеивается.

SET search_path TO reviewguard, public;

-- 1. Сводка дашборда: объём и доли тональностей.
-- Ожидается одна строка: 11 отзывов, 3 позитивных, 2 нейтральных, 6 негативных.
SELECT
    count(*) AS volume,
    count(*) FILTER (WHERE r.sentiment = 'positive') AS positive_count,
    count(*) FILTER (WHERE r.sentiment = 'neutral') AS neutral_count,
    count(*) FILTER (WHERE r.sentiment = 'negative') AS negative_count
FROM review AS r
WHERE r.organization_id = 1
  AND r.sentiment IS NOT NULL
  AND r.reviewed_at >= TIMESTAMPTZ '2026-03-01 00:00:00+00'
  AND r.reviewed_at < TIMESTAMPTZ '2026-04-01 00:00:00+00'
  AND r.object_id = 1;

-- 2. Динамика по суткам. Конец суток в выборку следующего дня не входит.
SELECT date_trunc('day', r.reviewed_at) AS day_start, count(*) AS volume
FROM review AS r
WHERE r.organization_id = 1
  AND r.sentiment IS NOT NULL
  AND r.reviewed_at >= TIMESTAMPTZ '2026-03-01 00:00:00+00'
  AND r.reviewed_at < TIMESTAMPTZ '2026-04-01 00:00:00+00'
  AND r.object_id = 1
GROUP BY date_trunc('day', r.reviewed_at)
ORDER BY day_start;

-- 3. Распределение по источникам. Ожидается Wildberries 6 и Ozon 5.
SELECT s.source_id, s.platform_name, count(*) AS volume
FROM review AS r
JOIN source AS s
  ON s.source_id = r.source_id
 AND s.organization_id = r.organization_id
 AND s.object_id = r.object_id
WHERE r.organization_id = 1
  AND r.sentiment IS NOT NULL
  AND r.reviewed_at >= TIMESTAMPTZ '2026-03-01 00:00:00+00'
  AND r.reviewed_at < TIMESTAMPTZ '2026-04-01 00:00:00+00'
  AND r.object_id = 1
GROUP BY s.source_id, s.platform_name
ORDER BY s.platform_name;

-- 4. Лента за период. Отзыв без даты в отбор по времени не входит.
-- Ожидаются отзывы 7, 6 и 5 источника Wildberries.
SELECT r.review_id, r.body, r.reviewed_at, r.sentiment, r.spam, s.platform_name
FROM review AS r
JOIN source AS s
  ON s.source_id = r.source_id
 AND s.organization_id = r.organization_id
WHERE r.organization_id = 1
  AND r.object_id = 1
  AND r.source_id = 1
  AND r.sentiment = 'negative'
  AND r.reviewed_at >= TIMESTAMPTZ '2026-03-20 00:00:00+00'
  AND r.reviewed_at < TIMESTAMPTZ '2026-03-21 00:00:00+00'
ORDER BY r.reviewed_at DESC, r.review_id DESC;

-- 4b. Лента без ограничения периода. Отзыв 8 без даты остаётся в выборке.
SELECT r.review_id, r.reviewed_at
FROM review AS r
WHERE r.organization_id = 1
  AND r.object_id = 1
  AND r.sentiment IS NOT NULL
ORDER BY r.reviewed_at DESC NULLS LAST, r.review_id DESC;

-- 5. Список аномалий организации.
SELECT a.anomaly_id, a.anomaly_type, a.status, o.name AS object_name,
       a.window_start, a.window_end, a.window_marked, a.window_total
FROM anomaly AS a
JOIN monitored_object AS o
  ON o.object_id = a.object_id
 AND o.organization_id = a.organization_id
WHERE a.organization_id = 1
ORDER BY a.opened_at DESC, a.anomaly_id DESC;

-- 6. Карточка аномалии и отзывы того же объекта.
SELECT a.anomaly_type, a.status, a.window_rate, a.baseline_rate,
       r.review_id, r.body, r.sentiment, r.spam
FROM anomaly AS a
JOIN anomaly_review AS ar
  ON ar.anomaly_id = a.anomaly_id
 AND ar.organization_id = a.organization_id
 AND ar.object_id = a.object_id
JOIN review AS r
  ON r.review_id = ar.review_id
 AND r.organization_id = ar.organization_id
 AND r.object_id = ar.object_id
WHERE a.organization_id = 1
  AND a.anomaly_id = 1
ORDER BY r.reviewed_at, r.review_id;

-- 7. Внутренние оповещения.
SELECT n.notification_id, n.message, n.anomaly_id, n.created_at
FROM notification AS n
WHERE n.organization_id = 1
ORDER BY n.created_at DESC, n.notification_id DESC;

-- 8. Чужая организация не попадает в сводку «Севера».
-- Ожидается 0.
SELECT count(*) AS foreign_rows
FROM review AS r
WHERE r.organization_id = 1
  AND r.object_id = 2;

-- 9. Смена статуса видит версию строки. Второе такое же сохранение не находит строку.
-- Откат оставляется, чтобы файл можно было выполнять целиком.
BEGIN;
UPDATE anomaly
   SET status = 'confirmed',
       version = version + 1,
       resolved_at = now(),
       resolved_by = 2
 WHERE anomaly_id = 1
   AND organization_id = 1
   AND version = 0;
UPDATE anomaly
   SET status = 'false_positive',
       version = version + 1,
       resolved_at = now(),
       resolved_by = 2
 WHERE anomaly_id = 1
   AND organization_id = 1
   AND version = 0;
ROLLBACK;

-- 10. Контроль контрольного набора. Любое расхождение прерывает скрипт.
DO $$
DECLARE
    volume integer;
    positive_count integer;
    neutral_count integer;
    negative_count integer;
    undated_count integer;
    card_count integer;
BEGIN
    SELECT count(*),
           count(*) FILTER (WHERE sentiment = 'positive'),
           count(*) FILTER (WHERE sentiment = 'neutral'),
           count(*) FILTER (WHERE sentiment = 'negative')
      INTO volume, positive_count, neutral_count, negative_count
      FROM review
     WHERE organization_id = 1
       AND sentiment IS NOT NULL
       AND reviewed_at >= TIMESTAMPTZ '2026-03-01 00:00:00+00'
       AND reviewed_at < TIMESTAMPTZ '2026-04-01 00:00:00+00';
    IF volume <> 11 OR positive_count <> 3 OR neutral_count <> 2 OR negative_count <> 6 THEN
        RAISE EXCEPTION 'bad dashboard counts: % / % / % / %',
            volume, positive_count, neutral_count, negative_count;
    END IF;

    SELECT count(*) INTO undated_count
      FROM review
     WHERE organization_id = 1
       AND reviewed_at IS NULL
       AND spam IS NULL;
    IF undated_count <> 1 THEN
        RAISE EXCEPTION 'expected one undated review, got %', undated_count;
    END IF;

    SELECT count(*) INTO card_count
      FROM anomaly_review
     WHERE anomaly_id = 1;
    IF card_count <> 6 THEN
        RAISE EXCEPTION 'negativity card expected 6 reviews, got %', card_count;
    END IF;
END $$;
