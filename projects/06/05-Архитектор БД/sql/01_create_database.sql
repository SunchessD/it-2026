-- ============================================================
-- Система контроля сроков домашних заданий студентов "task control"
-- Создание структуры базы данных (PostgreSQL)
-- ============================================================

-- ============================================================
-- 1. ПЕРЕЧИСЛЯЕМЫЕ ТИПЫ (ENUM)
-- ============================================================

-- Роль студента в группе
CREATE TYPE member_role AS ENUM ('admin', 'member');

-- Тип задания
CREATE TYPE task_kind AS ENUM ('personal', 'shared');

-- Статус задания для конкретного студента
CREATE TYPE task_state AS ENUM ('not_started', 'in_progress', 'done');

-- ============================================================
-- 2. СТУДЕНТЫ
-- ============================================================

CREATE TABLE students (
    student_id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 3. ГРУППЫ
-- ============================================================

CREATE TABLE groups (
    group_id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 4. УЧАСТНИКИ ГРУПП
-- ============================================================

CREATE TABLE group_members (
    student_id UUID NOT NULL REFERENCES students(student_id),
    group_id UUID NOT NULL REFERENCES groups(group_id),
    role member_role NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (student_id, group_id)
);

CREATE INDEX idx_group_members_group_id
    ON group_members(group_id);

-- ============================================================
-- 5. ПРИГЛАСИТЕЛЬНЫЕ ССЫЛКИ
-- ============================================================

-- PRIMARY KEY по group_id: одна актуальная запись-приглашение на группу.
CREATE TABLE invite_links (
    group_id UUID PRIMARY KEY REFERENCES groups(group_id),
    token UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. ЗАДАНИЯ
-- ============================================================

CREATE TABLE tasks (
    task_id UUID PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    due_at TIMESTAMPTZ NOT NULL,
    kind task_kind NOT NULL,
    author_id UUID NOT NULL REFERENCES students(student_id),
    group_id UUID REFERENCES groups(group_id),
    CONSTRAINT chk_tasks_kind_group
        CHECK ((kind = 'shared') = (group_id IS NOT NULL))
);

-- Индексы предусмотрены физической схемой.
CREATE INDEX idx_tasks_group_due_at
    ON tasks(group_id, due_at);

CREATE INDEX idx_tasks_author_due_at
    ON tasks(author_id, due_at);

-- ============================================================
-- 7. СТАТУСЫ ЗАДАНИЙ
-- ============================================================

-- Для одной пары (студент, задание) хранится один текущий статус.
CREATE TABLE task_statuses (
    student_id UUID NOT NULL REFERENCES students(student_id),
    task_id UUID NOT NULL REFERENCES tasks(task_id),
    status task_state NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (student_id, task_id)
);

CREATE INDEX idx_task_statuses_task_id
    ON task_statuses(task_id);


