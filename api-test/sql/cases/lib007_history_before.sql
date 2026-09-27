-- =============================================================
-- cases/lib007_history_before.sql  (LIB-007 の runnora: ブロックの before : 大量の貸出履歴)
-- M0004 に、B0005〜B0020 の 16 冊分の返却済み貸出履歴を一括投入する。
-- 5 件ずつ BULK COLLECT で読み、FORALL でまとめて INSERT する「バッチ処理」の定型。
--   loan 1..16 : 全て RETURNED (loaned_at は 1 週間ずつずらす)
--
-- 使用構文: BULK COLLECT ... LIMIT / FORALL / SQL%BULK_ROWCOUNT
--           入れ子表 (TABLE OF) / 基本 LOOP + EXIT WHEN
-- =============================================================
DECLARE
  CURSOR c_books IS
    SELECT book_id
      FROM books
     WHERE book_id BETWEEN 'B0005' AND 'B0020'
     ORDER BY book_id;

  TYPE t_ids   IS TABLE OF books.book_id%TYPE;
  TYPE t_dates IS TABLE OF DATE;
  v_ids     t_ids;
  v_loaned  t_dates := t_dates();
  v_offset  PLS_INTEGER := 0;
  v_batches PLS_INTEGER := 0;
  v_rows    PLS_INTEGER := 0;

  PROCEDURE log_hook(p_message IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO test_hook_log (hook_name, message) VALUES ('cases/lib007_history', p_message);
    COMMIT;
  END log_hook;
BEGIN
  OPEN c_books;
  LOOP
    FETCH c_books BULK COLLECT INTO v_ids LIMIT 5;
    EXIT WHEN v_ids.COUNT = 0;
    v_batches := v_batches + 1;

    -- 貸出日を事前に計算 (FORALL の中では式に添字しか使えないため)
    v_loaned.DELETE;
    v_loaned.EXTEND(v_ids.COUNT);
    FOR i IN 1 .. v_ids.COUNT LOOP
      v_loaned(i) := TRUNC(SYSDATE) - 200 + (v_offset + i) * 7;
    END LOOP;

    FORALL i IN 1 .. v_ids.COUNT
      INSERT INTO loans (loan_id, member_id, book_id, loaned_at, due_date, returned_at, status)
      VALUES (loan_seq.NEXTVAL, 'M0004', v_ids(i), v_loaned(i), v_loaned(i) + 14, v_loaned(i) + 10, 'RETURNED');

    FOR i IN 1 .. v_ids.COUNT LOOP
      v_rows := v_rows + SQL%BULK_ROWCOUNT(i);
    END LOOP;
    v_offset := v_offset + v_ids.COUNT;
  END LOOP;
  CLOSE c_books;

  IF v_rows <> 16 THEN
    RAISE_APPLICATION_ERROR(-20007, 'LIB-007: inserted ' || v_rows || ' rows (expected 16)');
  END IF;
  COMMIT;
  log_hook('batches=' || v_batches || ', rows=' || v_rows);
END;
