-- =============================================================
-- cases/lib005_savepoint_before.sql  (--before-sql : LIB-005 SAVEPOINT)
-- 「蔵書登録 + 初回貸出」を 1 単位として 5 件投入し、失敗した単位だけを
-- ROLLBACK TO SAVEPOINT で取り消して、成功した単位は最後にまとめて COMMIT する。
--
--   単位 | 蔵書  | ISBN            | 冊数 | 初回貸出 | 結果
--   -----+-------+-----------------+------+----------+-----------------------------
--    1   | B0101 | 9784000000101   | 2    | M0004    | 登録 (loan 1)
--    2   | B0102 | 9784000000102   | 1    | -        | 登録
--    3   | B0103 | 9784000000101   | 1    | -        | ISBN 重複 → 取消
--    4   | B0104 | 9784000000104   | 1    | M9999    | 蔵書は入るが貸出で FK 違反 → 蔵書ごと取消
--                                                       (loan 2 の採番は消費されたまま)
--    5   | B0105 | 9784000000105   | 3    | M0005    | 登録 (loan 3)
--
-- 後半は「一括の利用停止が想定件数を超えたら取り消し、個別停止に切り替える」例。
--
-- 使用構文: SAVEPOINT / ROLLBACK TO SAVEPOINT / ネストしたブロックの例外処理
--           DUP_VAL_ON_INDEX / PRAGMA EXCEPTION_INIT / 修飾式 / SQL%ROWCOUNT
--           PRAGMA AUTONOMOUS_TRANSACTION (ROLLBACK されないログ)
-- =============================================================
DECLARE
  TYPE t_unit IS RECORD (
    book_id books.book_id%TYPE,
    isbn    books.isbn%TYPE,
    copies  books.total_copies%TYPE,
    lend_to members.member_id%TYPE
  );
  TYPE t_units IS TABLE OF t_unit INDEX BY PLS_INTEGER;

  e_parent_missing EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_parent_missing, -2291);   -- ORA-02291: 親キーがありません

  v_units     t_units;
  v_loan_id   loans.loan_id%TYPE;
  v_ok        PLS_INTEGER := 0;
  v_rolled    PLS_INTEGER := 0;
  v_suspended PLS_INTEGER;

  PROCEDURE log_hook(p_message IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO test_hook_log (hook_name, message) VALUES ('cases/lib005_savepoint', p_message);
    COMMIT;
  END log_hook;
BEGIN
  v_units(1) := t_unit('B0101', '9784000000101', 2, 'M0004');
  v_units(2) := t_unit('B0102', '9784000000102', 1, NULL);
  v_units(3) := t_unit('B0103', '9784000000101', 1, NULL);      -- ISBN 重複
  v_units(4) := t_unit('B0104', '9784000000104', 1, 'M9999');   -- 存在しない会員
  v_units(5) := t_unit('B0105', '9784000000105', 3, 'M0005');

  FOR i IN 1 .. v_units.COUNT LOOP
    SAVEPOINT sp_unit;   -- 同名 SAVEPOINT は再設定すると位置が上書きされる
    BEGIN
      INSERT INTO books (book_id, isbn, title, author, genre, total_copies, available_copies)
      VALUES (v_units(i).book_id, v_units(i).isbn, 'SAVEPOINT 検証 ' || v_units(i).book_id,
              '試験 花子', 'TEST', v_units(i).copies, v_units(i).copies);

      IF v_units(i).lend_to IS NOT NULL THEN
        INSERT INTO loans (loan_id, member_id, book_id, loaned_at, due_date, status)
        VALUES (loan_seq.NEXTVAL, v_units(i).lend_to, v_units(i).book_id,
                TRUNC(SYSDATE), TRUNC(SYSDATE) + 14, 'ACTIVE')
        RETURNING loan_id INTO v_loan_id;

        UPDATE books SET available_copies = available_copies - 1
         WHERE book_id = v_units(i).book_id;
      END IF;
      v_ok := v_ok + 1;
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK TO SAVEPOINT sp_unit;
        v_rolled := v_rolled + 1;
        log_hook('rollback ' || v_units(i).book_id || ': duplicate isbn ' || v_units(i).isbn);
      WHEN e_parent_missing THEN
        -- 蔵書 INSERT は成功済み。SAVEPOINT まで戻すことで蔵書も一緒に取り消される
        ROLLBACK TO SAVEPOINT sp_unit;
        v_rolled := v_rolled + 1;
        log_hook('rollback ' || v_units(i).book_id || ': member ' || v_units(i).lend_to || ' not found');
    END;
  END LOOP;

  -- 後半: 一括停止 → 件数超過なら取り消して個別停止
  SAVEPOINT sp_before_suspend;
  UPDATE members SET status = 'SUSPENDED' WHERE member_id IN ('M0006', 'M0007', 'M0008');
  v_suspended := SQL%ROWCOUNT;   -- ROLLBACK 後は参照できないので先に退避する
  IF v_suspended > 1 THEN
    ROLLBACK TO SAVEPOINT sp_before_suspend;
    log_hook('rollback bulk suspend (' || v_suspended || ' rows); suspend M0008 only');
    UPDATE members SET status = 'SUSPENDED' WHERE member_id = 'M0008';
  END IF;

  COMMIT;
  log_hook('units ok=' || v_ok || ', rolled back=' || v_rolled);
END;
