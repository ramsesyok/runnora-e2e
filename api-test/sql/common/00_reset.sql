-- =============================================================
-- common/00_reset.sql  (config.yaml hooks.common.before 1/2)
-- 全テーブルのデータを削除し、貸出 ID の採番を 1 に戻す。
-- 毎回同じ初期状態から runbook を始めるための「リセット」フック。
--
-- 使用構文: VARRAY / 数値 FOR LOOP / EXECUTE IMMEDIATE (DML・DDL)
--           SQL%ROWCOUNT / DBMS_ASSERT / 局所プロシージャ
--           PRAGMA AUTONOMOUS_TRANSACTION
-- 注意: runnora はファイル全体を 1 文で実行するため、末尾に "/" を書かない。
-- =============================================================
DECLARE
  TYPE t_table_names IS VARRAY(10) OF VARCHAR2(30);
  -- 外部キーがあるため 子 → 親 の順に削除する
  c_tables  CONSTANT t_table_names := t_table_names('LOANS', 'BOOKS', 'MEMBERS');
  v_summary VARCHAR2(4000);

  -- 本体のトランザクションとは独立にログを確定させる (ROLLBACK されても残る)
  PROCEDURE log_hook(p_message IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO test_hook_log (hook_name, message) VALUES ('common/00_reset', p_message);
    COMMIT;
  END log_hook;
BEGIN
  FOR i IN 1 .. c_tables.COUNT LOOP
    -- 表名を動的 SQL に連結するので DBMS_ASSERT で識別子として検証する
    EXECUTE IMMEDIATE 'DELETE FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(c_tables(i));
    v_summary := v_summary || c_tables(i) || '=' || SQL%ROWCOUNT || ' ';
  END LOOP;

  -- 1 日より古いフックログを掃除する
  DELETE FROM test_hook_log WHERE logged_at < SYSTIMESTAMP - INTERVAL '1' DAY;
  COMMIT;

  -- DDL は暗黙コミットされるため、DML を確定させた後に実行する
  EXECUTE IMMEDIATE 'ALTER SEQUENCE loan_seq RESTART START WITH 1';

  log_hook('deleted rows: ' || RTRIM(v_summary) || ', loan_seq restarted');
END;
