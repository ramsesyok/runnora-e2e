-- =============================================================
-- cases/lib001_assert_after.sql  (LIB-001 の runnora: ブロックの after : 貸出〜返却)
-- API 経由では見えない DB 上の事後条件を検証する。
--   - 貸出は 1 件だけ作られ、RETURNED・返却日 = 本日 になっている
--   - B0001 の貸出可能冊数が初期値 3 に戻っている
--
-- 使用構文: SELECT INTO / 例外 NO_DATA_FOUND・TOO_MANY_ROWS
--           ユーザー定義例外 (EXCEPTION + RAISE) / RAISE_APPLICATION_ERROR
-- =============================================================
DECLARE
  e_assert   EXCEPTION;
  v_message  VARCHAR2(400);
  v_loan     loans%ROWTYPE;
  v_avail    books.available_copies%TYPE;
BEGIN
  -- 1 件だけであることを SELECT INTO の例外で確かめる
  SELECT * INTO v_loan FROM loans WHERE member_id = 'M0001';

  IF v_loan.loan_id <> 1 OR v_loan.book_id <> 'B0001' THEN
    v_message := 'unexpected loan: id=' || v_loan.loan_id || ' book=' || v_loan.book_id;
    RAISE e_assert;
  ELSIF v_loan.status <> 'RETURNED' OR v_loan.returned_at <> TRUNC(SYSDATE) THEN
    v_message := 'loan 1 is not returned today: status=' || v_loan.status
                 || ' returned_at=' || TO_CHAR(v_loan.returned_at, 'YYYY-MM-DD');
    RAISE e_assert;
  END IF;

  SELECT available_copies INTO v_avail FROM books WHERE book_id = 'B0001';
  IF v_avail <> 3 THEN
    v_message := 'B0001 available_copies=' || v_avail || ' (expected 3)';
    RAISE e_assert;
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'LIB-001: no loan found for M0001');
  WHEN TOO_MANY_ROWS THEN
    RAISE_APPLICATION_ERROR(-20001, 'LIB-001: more than one loan found for M0001');
  WHEN e_assert THEN
    RAISE_APPLICATION_ERROR(-20001, 'LIB-001: ' || v_message);
END;
