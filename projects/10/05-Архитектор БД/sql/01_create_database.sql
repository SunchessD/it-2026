-- ============================================================
-- Веб-приложение для организации онлайн-обучения и тестирования
-- Команда № 10
-- Скрипт создания структуры базы данных (PostgreSQL 14+)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- 1. МОДУЛЬ: УЧЁТНЫЕ ЗАПИСИ И АУТЕНТИФИКАЦИЯ
-- ------------------------------------------------------------

-- Пользователи системы
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL CHECK (length(trim(name)) > 0),
    email VARCHAR(254) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(16) NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
    status VARCHAR(16) NOT NULL DEFAULT 'inactive' CHECK (status IN ('inactive', 'active', 'blocked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Токены подтверждения адреса электронной почты
CREATE TABLE email_activation_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at)
);

-- ------------------------------------------------------------
-- 2. МОДУЛЬ: КАТАЛОГ И УЧЕБНЫЕ МАТЕРИАЛЫ КУРСОВ
-- ------------------------------------------------------------

-- Категории курсов
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    CHECK (length(trim(name)) > 0)
);

-- Образовательные курсы
CREATE TABLE courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL CHECK (length(trim(title)) > 0),
    description TEXT NOT NULL DEFAULT '',
    difficulty VARCHAR(20) NOT NULL CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
    status VARCHAR(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'published')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Тематические модули курса
CREATE TABLE modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position > 0),
    title VARCHAR(200) NOT NULL CHECK (length(trim(title)) > 0),
    description TEXT,
    UNIQUE (course_id, position)
);

-- Учебные занятия (уроки)
CREATE TABLE lessons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id UUID NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position > 0),
    title VARCHAR(200) NOT NULL CHECK (length(trim(title)) > 0),
    content TEXT NOT NULL DEFAULT '',
    UNIQUE (module_id, position)
);

-- Проверочные тесты модулей
CREATE TABLE tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id UUID NOT NULL UNIQUE REFERENCES modules(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL CHECK (length(trim(title)) > 0),
    passing_score_percent SMALLINT NOT NULL CHECK (passing_score_percent BETWEEN 0 AND 100),
    time_limit_minutes INTEGER NOT NULL CHECK (time_limit_minutes > 0)
);

-- Вопросы проверочного теста
CREATE TABLE questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id UUID NOT NULL REFERENCES tests(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position > 0),
    question_text TEXT NOT NULL CHECK (length(trim(question_text)) > 0),
    question_type VARCHAR(20) NOT NULL CHECK (question_type IN ('single', 'multiple', 'text')),
    points INTEGER NOT NULL CHECK (points > 0),
    UNIQUE (test_id, position)
);

-- Варианты ответов на вопросы
CREATE TABLE answer_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position > 0),
    answer_text TEXT NOT NULL CHECK (length(trim(answer_text)) > 0),
    is_correct BOOLEAN NOT NULL DEFAULT false,
    UNIQUE (question_id, position)
);

-- ------------------------------------------------------------
-- 3. МОДУЛЬ: ОБУЧЕНИЕ, ТЕСТИРОВАНИЕ И СЕРТИФИКАЦИЯ
-- ------------------------------------------------------------

-- Зачисление студентов на курс
CREATE TABLE enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
    progress_percent SMALLINT NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'withdrawn')),
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (student_id, course_id)
);

-- Отметки о прохождении занятий
CREATE TABLE lesson_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
    lesson_id UUID NOT NULL REFERENCES lessons(id) ON DELETE RESTRICT,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (enrollment_id, lesson_id)
);

-- Попытки прохождения тестов
CREATE TABLE test_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES tests(id) ON DELETE RESTRICT,
    score_percent SMALLINT CHECK (score_percent BETWEEN 0 AND 100),
    status VARCHAR(16) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'passed', 'failed')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    CHECK (
        (status = 'in_progress' AND score_percent IS NULL AND finished_at IS NULL)
        OR
        (status IN ('passed', 'failed') AND score_percent IS NOT NULL AND finished_at IS NOT NULL AND finished_at >= started_at)
    )
);

-- Ответы студента в рамках попытки
CREATE TABLE attempt_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL REFERENCES test_attempts(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
    text_answer TEXT,
    is_correct BOOLEAN,
    UNIQUE (attempt_id, question_id)
);

-- Выбранные варианты ответов студента
CREATE TABLE attempt_answer_options (
    attempt_answer_id UUID NOT NULL REFERENCES attempt_answers(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES answer_options(id) ON DELETE RESTRICT,
    PRIMARY KEY (attempt_answer_id, option_id)
);

-- Сертификаты об окончании обучения
CREATE TABLE certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL UNIQUE REFERENCES enrollments(id) ON DELETE RESTRICT,
    certificate_number VARCHAR(64) NOT NULL UNIQUE,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- 4. МОДУЛЬ: МОДЕРАЦИЯ
-- ------------------------------------------------------------

-- Решения по модерации курсов
CREATE TABLE moderation_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    decision VARCHAR(12) NOT NULL CHECK (decision IN ('approved', 'rejected')),
    comment TEXT,
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (decision <> 'rejected' OR (comment IS NOT NULL AND length(trim(comment)) > 0))
);

-- ------------------------------------------------------------
-- 5. ИНДЕКСЫ ДЛЯ ОПТИМИЗАЦИИ ЗАПРОСОВ
-- ------------------------------------------------------------

CREATE INDEX idx_activation_tokens_user ON email_activation_tokens(user_id, expires_at);
CREATE INDEX idx_courses_catalog ON courses(status, category_id, difficulty);
CREATE INDEX idx_courses_author ON courses(author_id, status);
CREATE INDEX idx_modules_course_pos ON modules(course_id, position);
CREATE INDEX idx_lessons_module_pos ON lessons(module_id, position);
CREATE INDEX idx_enrollments_student ON enrollments(student_id, status);
CREATE INDEX idx_lesson_completions_enrollment ON lesson_completions(enrollment_id);
CREATE INDEX idx_attempts_enrollment_test_start ON test_attempts(enrollment_id, test_id, started_at DESC);
CREATE INDEX idx_moderation_course_date ON moderation_decisions(course_id, decided_at DESC);
