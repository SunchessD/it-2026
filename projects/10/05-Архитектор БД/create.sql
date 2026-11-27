CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name varchar(150) NOT NULL CHECK (length(trim(name)) > 0),
 email varchar(254) NOT NULL UNIQUE,
 password_hash text NOT NULL,
 role varchar(16) NOT NULL CHECK (role IN ('student','teacher','admin')),
 status varchar(16) NOT NULL DEFAULT 'inactive' CHECK (status IN ('inactive','active','blocked')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE email_activation_tokens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 token_hash varchar(128) NOT NULL UNIQUE,
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (expires_at > created_at)
);
CREATE TABLE categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name varchar(120) NOT NULL UNIQUE,
 description text,
 CHECK (length(trim(name)) > 0)
);
CREATE TABLE courses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 author_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
 category_id uuid NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
 title varchar(200) NOT NULL CHECK (length(trim(title)) > 0),
 description text NOT NULL DEFAULT '',
 difficulty varchar(20) NOT NULL CHECK (difficulty IN ('beginner','intermediate','advanced')),
 status varchar(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending','published')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE modules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
 position integer NOT NULL CHECK (position > 0),
 title varchar(200) NOT NULL CHECK (length(trim(title)) > 0),
 description text,
 UNIQUE (course_id, position)
);
CREATE TABLE lessons (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 module_id uuid NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
 position integer NOT NULL CHECK (position > 0),
 title varchar(200) NOT NULL CHECK (length(trim(title)) > 0),
 content text NOT NULL DEFAULT '',
 UNIQUE (module_id, position)
);
CREATE TABLE tests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 module_id uuid NOT NULL UNIQUE REFERENCES modules(id) ON DELETE CASCADE,
 title varchar(200) NOT NULL CHECK (length(trim(title)) > 0),
 passing_score_percent smallint NOT NULL CHECK (passing_score_percent BETWEEN 0 AND 100),
 time_limit_minutes integer NOT NULL CHECK (time_limit_minutes > 0)
);
CREATE TABLE questions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 test_id uuid NOT NULL REFERENCES tests(id) ON DELETE CASCADE,
 position integer NOT NULL CHECK (position > 0),
 question_text text NOT NULL CHECK (length(trim(question_text)) > 0),
 question_type varchar(20) NOT NULL CHECK (question_type IN ('single','multiple','text')),
 points integer NOT NULL CHECK (points > 0),
 UNIQUE (test_id, position)
);
CREATE TABLE answer_options (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
 position integer NOT NULL CHECK (position > 0),
 answer_text text NOT NULL CHECK (length(trim(answer_text)) > 0),
 is_correct boolean NOT NULL DEFAULT false,
 UNIQUE (question_id, position)
);
CREATE TABLE enrollments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 student_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
 course_id uuid NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
 progress_percent smallint NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
 status varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','withdrawn')),
 enrolled_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (student_id, course_id)
);
CREATE TABLE lesson_completions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 enrollment_id uuid NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
 lesson_id uuid NOT NULL REFERENCES lessons(id) ON DELETE RESTRICT,
 completed_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (enrollment_id, lesson_id)
);
CREATE TABLE test_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 enrollment_id uuid NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
 test_id uuid NOT NULL REFERENCES tests(id) ON DELETE RESTRICT,
 score_percent smallint CHECK (score_percent BETWEEN 0 AND 100),
 status varchar(16) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','passed','failed')),
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 CHECK ((status = 'in_progress' AND score_percent IS NULL AND finished_at IS NULL)
    OR (status IN ('passed','failed') AND score_percent IS NOT NULL AND finished_at IS NOT NULL AND finished_at >= started_at))
);
CREATE TABLE attempt_answers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 attempt_id uuid NOT NULL REFERENCES test_attempts(id) ON DELETE CASCADE,
 question_id uuid NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
 text_answer text,
 is_correct boolean,
 UNIQUE (attempt_id, question_id)
);
CREATE TABLE attempt_answer_options (
 attempt_answer_id uuid NOT NULL REFERENCES attempt_answers(id) ON DELETE CASCADE,
 option_id uuid NOT NULL REFERENCES answer_options(id) ON DELETE RESTRICT,
 PRIMARY KEY (attempt_answer_id, option_id)
);
CREATE TABLE certificates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 enrollment_id uuid NOT NULL UNIQUE REFERENCES enrollments(id) ON DELETE RESTRICT,
 certificate_number varchar(64) NOT NULL UNIQUE,
 issued_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE moderation_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
 admin_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
 decision varchar(12) NOT NULL CHECK (decision IN ('approved','rejected')),
 comment text,
 decided_at timestamptz NOT NULL DEFAULT now(),
 CHECK (decision <> 'rejected' OR (comment IS NOT NULL AND length(trim(comment)) > 0))
);

CREATE INDEX idx_activation_tokens_user ON email_activation_tokens(user_id, expires_at);
CREATE INDEX idx_courses_catalog ON courses(status, category_id, difficulty);
CREATE INDEX idx_courses_author ON courses(author_id, status);
CREATE INDEX idx_enrollments_student ON enrollments(student_id, status);
CREATE INDEX idx_lesson_completions_enrollment ON lesson_completions(enrollment_id);
CREATE INDEX idx_attempts_enrollment_test_start ON test_attempts(enrollment_id, test_id, started_at DESC);
CREATE INDEX idx_moderation_course_date ON moderation_decisions(course_id, decided_at DESC);
