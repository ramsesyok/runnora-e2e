-- =============================================================
-- cases/lib003_overdue_before.sql  (LIB-003 の runnora: ブロックの before : 延滞者の貸出拒否)
-- API では作れない「返却期限を 7 日過ぎた貸出」を直接作る。
--   loan 1 : M0002 が B0004 を 21 日前に借りて未返却 (期限は 7 日前)
--
-- 使用構文: %ROWTYPE レコード / レコード単位の INSERT (VALUES rec)
--           PL/SQL 式でのシーケンス参照 / 日付演算 / RETURNING INTO
-- =============================================================
DECLARE
  v_loan  loans%ROWTYPE;
  v_title books.title%TYPE;
BEGIN
  v_loan.loan_id     := loan_seq.NEXTVAL;
  v_loan.member_id   := 'M0002';
  v_loan.book_id     := 'B0004';
  v_loan.loaned_at   := TRUNC(SYSDATE) - 21;
  v_loan.due_date    := v_loan.loaned_at + 14;    -- = 7 日前
  v_loan.returned_at := NULL;
  v_loan.status      := 'ACTIVE';

  INSERT INTO loans VALUES v_loan;

  -- 不変条件 (貸出可能冊数 = 所蔵 - 貸出中) を保つため在庫も減らす
  UPDATE books
     SET available_copies = available_copies - 1
   WHERE book_id = v_loan.book_id
  RETURNING title INTO v_title;

  IF SQL%ROWCOUNT <> 1 THEN
    RAISE_APPLICATION_ERROR(-20003, 'LIB-003: book ' || v_loan.book_id || ' not found');
  END IF;
  COMMIT;
END;
