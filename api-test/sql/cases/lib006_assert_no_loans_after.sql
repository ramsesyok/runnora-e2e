-- =============================================================
-- cases/lib006_assert_no_loans_after.sql  (LIB-006 の runnora: ブロックの after : 異常系)
-- エラー応答を返したリクエストが DB を変更していないことを確認する。
--   - 貸出は 0 件 / 蔵書は初期の 20 件 / 採番は一度も進んでいない
--
-- 使用構文: SELECT INTO / USER_SEQUENCES の参照 / IF ... ELSIF
-- =============================================================
DECLARE
  v_loans  PLS_INTEGER;
  v_books  PLS_INTEGER;
  v_nextno NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_loans FROM loans;
  SELECT COUNT(*) INTO v_books FROM books;
  -- NOCACHE なので LAST_NUMBER = 次に払い出される値
  SELECT last_number INTO v_nextno FROM user_sequences WHERE sequence_name = 'LOAN_SEQ';

  IF v_loans <> 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'LIB-006: loans=' || v_loans || ' (expected 0)');
  ELSIF v_books <> 20 THEN
    RAISE_APPLICATION_ERROR(-20006, 'LIB-006: books=' || v_books || ' (expected 20)');
  ELSIF v_nextno <> 1 THEN
    RAISE_APPLICATION_ERROR(-20006, 'LIB-006: loan_seq advanced to ' || v_nextno);
  END IF;
END;
