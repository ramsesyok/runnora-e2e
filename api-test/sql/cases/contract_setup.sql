-- =============================================================
-- cases/contract_setup.sql  (runnora.yaml のスイート generated-unit / contract-unit の hooks.before)
-- モック (oapi2wire) と同じ前提データを実 DB に作る。
--   loan 1 : M0002 が B0003 を貸出中 (ACTIVE)   → POST /loans/1/return は 200
--   loan 2 : M0002 が B0004 を返却済 (RETURNED) → POST /loans/2/return は 409
--
-- 使用構文: 行ロック (SELECT ... FOR UPDATE) / RETURNING INTO / 局所プロシージャ
-- =============================================================
DECLARE
  v_loan_id loans.loan_id%TYPE;
  v_avail   books.available_copies%TYPE;

  PROCEDURE lend(p_member IN VARCHAR2, p_book IN VARCHAR2, p_days_ago IN PLS_INTEGER,
                 p_returned IN BOOLEAN, p_loan_id OUT NUMBER) IS
  BEGIN
    -- API と同じく蔵書行をロックしてから在庫を動かす
    SELECT available_copies INTO v_avail FROM books WHERE book_id = p_book FOR UPDATE;

    INSERT INTO loans (loan_id, member_id, book_id, loaned_at, due_date, returned_at, status)
    VALUES (loan_seq.NEXTVAL, p_member, p_book,
            TRUNC(SYSDATE) - p_days_ago, TRUNC(SYSDATE) - p_days_ago + 14,
            CASE WHEN p_returned THEN TRUNC(SYSDATE) - p_days_ago + 9 END,
            CASE WHEN p_returned THEN 'RETURNED' ELSE 'ACTIVE' END)
    RETURNING loan_id INTO p_loan_id;

    IF NOT p_returned THEN
      UPDATE books SET available_copies = v_avail - 1 WHERE book_id = p_book;
    END IF;
  END lend;
BEGIN
  lend('M0002', 'B0003', 6,  FALSE, v_loan_id);   -- loan 1 (ACTIVE)
  lend('M0002', 'B0004', 25, TRUE,  v_loan_id);   -- loan 2 (RETURNED)
  COMMIT;
END;
