-- =============================================================
-- 01_create_user.sql : アプリ用スキーマ LIBAPP を作成する (SYS / FREEPDB1 で実行)
-- 何度実行しても同じ状態になるよう、既存ユーザーは削除してから作り直す。
-- =============================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;

DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'LIBAPP';
  IF v_cnt > 0 THEN
    -- API や runnora が接続中だと DROP USER が ORA-01940 になるため、
    -- 新規接続を止めてから既存セッションを切断する
    EXECUTE IMMEDIATE 'ALTER USER libapp ACCOUNT LOCK';
    FOR s IN (SELECT sid, serial# AS serial FROM v$session WHERE username = 'LIBAPP') LOOP
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial || ''' IMMEDIATE';
    END LOOP;
    EXECUTE IMMEDIATE 'DROP USER libapp CASCADE';
  END IF;
END;
/

CREATE USER libapp IDENTIFIED BY libapp_pw
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE VIEW,
      CREATE PROCEDURE, CREATE TRIGGER TO libapp;
EXIT
