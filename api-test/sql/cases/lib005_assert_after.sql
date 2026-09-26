-- =============================================================
-- cases/lib005_assert_after.sql  (--after-sql : LIB-005 SAVEPOINT)
-- SAVEPOINT で取り消した単位が残っていないこと、API で再登録した B0103 が
-- 追加されていることを DB で確認する。
--
-- 使用構文: 集計の SELECT INTO / 条件付き COUNT / RAISE_APPLICATION_ERROR
-- =============================================================
DECLARE
  v_test_books PLS_INTEGER;
  v_b0104      PLS_INTEGER;
  v_rollbacks  PLS_INTEGER;
BEGIN
  SELECT COUNT(*), COUNT(CASE WHEN book_id = 'B0104' THEN 1 END)
    INTO v_test_books, v_b0104
    FROM books
   WHERE genre = 'TEST';

  -- 前処理で 3 件 (B0101, B0102, B0105) + シナリオ内の API 登録 1 件 (B0103)
  IF v_test_books <> 4 THEN
    RAISE_APPLICATION_ERROR(-20005, 'LIB-005: TEST books=' || v_test_books || ' (expected 4)');
  END IF;
  IF v_b0104 <> 0 THEN
    RAISE_APPLICATION_ERROR(-20005, 'LIB-005: B0104 should have been rolled back');
  END IF;

  -- 自律型トランザクションのログは ROLLBACK TO の影響を受けずに残っている
  SELECT COUNT(*) INTO v_rollbacks
    FROM test_hook_log
   WHERE hook_name = 'cases/lib005_savepoint'
     AND message LIKE 'rollback B%'
     AND logged_at > SYSTIMESTAMP - INTERVAL '10' MINUTE;
  IF v_rollbacks < 2 THEN
    RAISE_APPLICATION_ERROR(-20005, 'LIB-005: rollback log count=' || v_rollbacks || ' (expected >= 2)');
  END IF;
END;
