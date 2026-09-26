-- =============================================================
-- 02_schema.sql : 図書貸出 API のテーブル定義 (LIBAPP で実行)
-- =============================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- 会員
CREATE TABLE members (
  member_id   VARCHAR2(10)  PRIMARY KEY,
  name        VARCHAR2(100) NOT NULL,
  status      VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL
              CONSTRAINT members_status_ck CHECK (status IN ('ACTIVE', 'SUSPENDED')),
  max_loans   NUMBER(2)     DEFAULT 3 NOT NULL,
  created_at  DATE          DEFAULT SYSDATE NOT NULL
);

-- 蔵書 (1 タイトル = 1 行。所蔵冊数と貸出可能冊数を持つ)
CREATE TABLE books (
  book_id          VARCHAR2(10)  PRIMARY KEY,
  isbn             VARCHAR2(13)  NOT NULL CONSTRAINT books_isbn_uk UNIQUE,
  title            VARCHAR2(200) NOT NULL,
  author           VARCHAR2(100) NOT NULL,
  genre            VARCHAR2(20)  NOT NULL,
  total_copies     NUMBER(3)     NOT NULL CONSTRAINT books_total_ck CHECK (total_copies >= 0),
  available_copies NUMBER(3)     NOT NULL,
  created_at       DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT books_avail_ck CHECK (available_copies BETWEEN 0 AND total_copies)
);

-- 貸出 ID 採番用。before フックで RESTART して ID を決定的にする
CREATE SEQUENCE loan_seq START WITH 1 INCREMENT BY 1 NOCACHE;

-- 貸出
CREATE TABLE loans (
  loan_id     NUMBER(10)    PRIMARY KEY,
  member_id   VARCHAR2(10)  NOT NULL REFERENCES members(member_id),
  book_id     VARCHAR2(10)  NOT NULL REFERENCES books(book_id),
  loaned_at   DATE          NOT NULL,
  due_date    DATE          NOT NULL,
  returned_at DATE,
  status      VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL
              CONSTRAINT loans_status_ck CHECK (status IN ('ACTIVE', 'RETURNED'))
);
CREATE INDEX loans_member_ix ON loans(member_id, status);

-- テストフック実行ログ (自律型トランザクションで書き込む)
CREATE TABLE test_hook_log (
  log_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hook_name  VARCHAR2(100) NOT NULL,
  message    VARCHAR2(4000),
  -- SYSTIMESTAMP と比較するため TIME ZONE 付きにする (TZ なし TIMESTAMP はセッション TZ で解釈され、
  -- go-ora はクライアント OS の TZ をセッションに設定するので比較結果が環境依存になる)
  logged_at  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);
EXIT
