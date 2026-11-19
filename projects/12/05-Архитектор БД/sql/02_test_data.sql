-- Демонстрационные данные RoomBook.
-- Используются фиктивные учётные данные; парольные хеши не предназначены для входа.
SET search_path TO roombook, public;

INSERT INTO users (user_id, email, full_name, role, password_hash) VALUES
    (1, 'student@example.edu', 'Иван Петров', 'student', '$2b$12$DEMO_ONLY_NOT_A_VALID_PASSWORD_HASH'),
    (2, 'teacher@example.edu', 'Анна Смирнова', 'teacher', '$2b$12$DEMO_ONLY_NOT_A_VALID_PASSWORD_HASH'),
    (3, 'dispatcher@example.edu', 'Ольга Иванова', 'dispatcher', '$2b$12$DEMO_ONLY_NOT_A_VALID_PASSWORD_HASH');

INSERT INTO buildings (building_id, name, address, opens_at, closes_at) VALUES
    (1, 'Главный корпус', 'Политехническая улица, 29', '08:00', '22:00'),
    (2, 'Корпус Б', 'Политехническая улица, 31', '09:00', '20:00');

INSERT INTO rooms (room_id, building_id, room_number, capacity, is_bookable) VALUES
    (1, 1, '214', 30, true),
    (2, 1, '305', 50, true),
    (3, 2, 'Б-12', 18, true),
    (4, 2, 'Б-14', 24, false);

INSERT INTO equipment (equipment_id, name) VALUES
    (1, 'Проектор'),
    (2, 'Компьютер'),
    (3, 'Интерактивная доска');

INSERT INTO room_equipment (room_id, equipment_id, quantity) VALUES
    (1, 1, 1), (1, 2, 1),
    (2, 1, 1), (2, 3, 1),
    (3, 1, 1), (3, 2, 8);

-- Основное расписание: по средам в аудитории 214 проходит занятие 10:00–11:30.
INSERT INTO schedule_entries
    (schedule_entry_id, room_id, teacher_id, weekday, discipline, study_group,
     valid_from, valid_until, starts_at, ends_at)
VALUES
    (1, 1, 2, 3, 'Базы данных', 'ИВТ-21', '2026-09-01', '2026-12-31', '10:00', '11:30');

-- Заявка студента ожидает диспетчера. Бронь преподавателя подтверждена и не
-- пересекается с расписанием и другими подтверждёнными бронями аудитории.
INSERT INTO bookings
    (booking_id, room_id, author_id, booking_date, starts_at, ends_at,
     purpose, participant_count, status)
VALUES
    (1, 1, 1, '2026-12-02', '12:00', '13:30', 'Собрание студенческого клуба', 18, 'pending'),
    (2, 2, 2, '2026-12-03', '16:00', '17:30', 'Консультация по курсу', 25, 'confirmed');

INSERT INTO booking_status_history
    (booking_id, changed_by, old_status, new_status, reason)
VALUES
    (1, 1, NULL, 'pending', 'Заявка создана пользователем'),
    (2, 2, NULL, 'confirmed', 'Бронирование преподавателя создано');

INSERT INTO notifications (recipient_id, booking_id, message, is_read) VALUES
    (1, 1, 'Заявка на аудиторию 214 отправлена диспетчеру', false),
    (2, 2, 'Бронирование аудитории 305 подтверждено', true);

-- Синхронизация identity-последовательностей после явной установки ключей.
SELECT setval(pg_get_serial_sequence('roombook.users', 'user_id'),
              (SELECT max(user_id) FROM users));
SELECT setval(pg_get_serial_sequence('roombook.buildings', 'building_id'),
              (SELECT max(building_id) FROM buildings));
SELECT setval(pg_get_serial_sequence('roombook.rooms', 'room_id'),
              (SELECT max(room_id) FROM rooms));
SELECT setval(pg_get_serial_sequence('roombook.equipment', 'equipment_id'),
              (SELECT max(equipment_id) FROM equipment));
SELECT setval(pg_get_serial_sequence('roombook.schedule_entries', 'schedule_entry_id'),
              (SELECT max(schedule_entry_id) FROM schedule_entries));
SELECT setval(pg_get_serial_sequence('roombook.bookings', 'booking_id'),
              (SELECT max(booking_id) FROM bookings));
SELECT setval(pg_get_serial_sequence('roombook.booking_status_history', 'history_id'),
              (SELECT max(history_id) FROM booking_status_history));
SELECT setval(pg_get_serial_sequence('roombook.notifications', 'notification_id'),
              (SELECT max(notification_id) FROM notifications));
