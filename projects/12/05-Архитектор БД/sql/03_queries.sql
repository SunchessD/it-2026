-- Примеры запросов RoomBook (PostgreSQL).
SET search_path TO roombook, public;

-- 1. Каталог аудиторий корпуса с вместимостью и оборудованием.
SELECT b.name AS building, r.room_number, r.capacity,
       COALESCE(string_agg(e.name || ' × ' || re.quantity, ', ' ORDER BY e.name), 'нет') AS equipment
  FROM rooms r
  JOIN buildings b ON b.building_id = r.building_id
  LEFT JOIN room_equipment re ON re.room_id = r.room_id
  LEFT JOIN equipment e ON e.equipment_id = re.equipment_id
 WHERE r.is_bookable
 GROUP BY b.name, r.room_number, r.capacity
 ORDER BY b.name, r.room_number;

-- 2. Найти подходящие свободные аудитории на дату и время.
-- $1 = дата, $2 = начало, $3 = окончание, $4 = минимум мест.
SELECT r.room_id, b.name AS building, r.room_number, r.capacity
  FROM rooms r
  JOIN buildings b ON b.building_id = r.building_id
 WHERE r.is_bookable
   AND r.capacity >= $4
   AND $2::time >= b.opens_at
   AND $3::time <= b.closes_at
   AND NOT EXISTS (
       SELECT 1 FROM bookings bk
        WHERE bk.room_id = r.room_id
          AND bk.status = 'confirmed'
          AND bk.booking_slot && tsrange($1::date + $2::time, $1::date + $3::time, '[)')
   )
   AND NOT EXISTS (
       SELECT 1 FROM schedule_entries s
        WHERE s.room_id = r.room_id
          AND s.weekday = extract(isodow FROM $1::date)::smallint
          AND $1::date BETWEEN s.valid_from AND s.valid_until
          AND s.starts_at < $3::time
          AND s.ends_at > $2::time
   )
 ORDER BY r.capacity, b.name, r.room_number;

-- 3. Создать заявку студента. Проверки доступности повторяются при подтверждении,
-- поскольку свободный слот может измениться между подачей и решением диспетчера.
INSERT INTO bookings
    (room_id, author_id, booking_date, starts_at, ends_at, purpose, participant_count, status)
VALUES
    ($1, $2, $3, $4, $5, $6, $7, 'pending')
RETURNING booking_id, status, created_at;

-- 4. Бронирования текущего пользователя с адресом аудитории и корпуса.
SELECT bk.booking_id, bk.booking_date, bk.starts_at, bk.ends_at,
       b.name AS building, r.room_number, bk.purpose, bk.status
  FROM bookings bk
  JOIN rooms r ON r.room_id = bk.room_id
  JOIN buildings b ON b.building_id = r.building_id
 WHERE bk.author_id = $1
 ORDER BY bk.created_at DESC;

-- 5. Заявки, ожидающие решения диспетчера.
SELECT bk.booking_id, bk.booking_date, bk.starts_at, bk.ends_at,
       u.full_name AS author, u.email, b.name AS building, r.room_number,
       bk.purpose, bk.participant_count
  FROM bookings bk
  JOIN users u ON u.user_id = bk.author_id
  JOIN rooms r ON r.room_id = bk.room_id
  JOIN buildings b ON b.building_id = r.building_id
 WHERE bk.status = 'pending'
 ORDER BY bk.created_at;

-- 6. Подтверждение диспетчером. Выполнять в транзакции; если слот занят или
-- пересекается с основным расписанием, триггер/ограничение отклонит UPDATE.
-- $1 = booking_id, $2 = dispatcher user_id.
BEGIN;
WITH changed AS (
    UPDATE bookings
       SET status = 'confirmed'
     WHERE booking_id = $1 AND status = 'pending'
     RETURNING booking_id, author_id
), history AS (
    INSERT INTO booking_status_history (booking_id, changed_by, old_status, new_status)
    SELECT booking_id, $2, 'pending', 'confirmed' FROM changed
    RETURNING booking_id
)
INSERT INTO notifications (recipient_id, booking_id, message)
SELECT changed.author_id, changed.booking_id, 'Бронирование подтверждено диспетчером'
  FROM changed
  JOIN history USING (booking_id);
-- Если заявка уже не pending, UPDATE затронет ноль строк и связанные CTE
-- ничего не добавят. Приложение проверяет число изменённых строк и сообщает об этом.
COMMIT;

-- 7. История решений по бронированию.
SELECT h.changed_at, h.old_status, h.new_status, h.reason,
       u.full_name AS changed_by
  FROM booking_status_history h
  JOIN users u ON u.user_id = h.changed_by
 WHERE h.booking_id = $1
 ORDER BY h.changed_at, h.history_id;

-- 8. Непрочитанные уведомления пользователя.
SELECT notification_id, message, created_at
  FROM notifications
 WHERE recipient_id = $1 AND NOT is_read
 ORDER BY created_at DESC;

-- 9. Поиск занятий основного расписания для аудитории на дату.
SELECT s.discipline, s.study_group, s.starts_at, s.ends_at, u.full_name AS teacher
  FROM schedule_entries s
  JOIN users u ON u.user_id = s.teacher_id
 WHERE s.room_id = $1
   AND s.weekday = extract(isodow FROM $2::date)::smallint
   AND $2::date BETWEEN s.valid_from AND s.valid_until
 ORDER BY s.starts_at;
