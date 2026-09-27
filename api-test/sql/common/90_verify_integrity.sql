-- =============================================================
-- common/90_verify_integrity.sql  (runnora.yaml の環境 unit の hooks.after)
-- runbook 実行後に DB の不変条件を検証する。違反があれば
-- RAISE_APPLICATION_ERROR で失敗させる (フック失敗。期待していなければ runnora は exit 4 で終了する)。
--
-- 不変条件:
--   (1) 蔵書ごとに 貸出可能冊数 = 所蔵冊数 - 貸出中件数
--   (2) ACTIVE の貸出は返却日なし / RETURNED の貸出は返却日あり
--   (3) 会員の貸出中件数 <= 貸出上限
--
-- 使用構文: カーソル FOR LOOP / CASE 文 / 局所プロシージャ
--           PRAGMA AUTONOMOUS_TRANSACTION / RAISE_APPLICATION_ERROR
-- =============================================================
DECLARE
  v_errors  PLS_INTEGER := 0;
  v_checked PLS_INTEGER := 0;
  v_detail  VARCHAR2(4000);

  PROCEDURE add_error(p_message IN VARCHAR2) IS
  BEGIN
    v_errors := v_errors + 1;
    IF NVL(LENGTH(v_detail), 0) < 3000 THEN
      v_detail := v_detail || p_message || '; ';
    END IF;
  END add_error;

  PROCEDURE log_hook(p_message IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO test_hook_log (hook_name, message) VALUES ('common/90_verify_integrity', p_message);
    COMMIT;
  END log_hook;
BEGIN
  -- (1) 在庫数の整合 : カーソル FOR LOOP
  FOR r IN (
    SELECT b.book_id, b.total_copies, b.available_copies, COUNT(l.loan_id) AS active_loans
      FROM books b
      LEFT JOIN loans l ON l.book_id = b.book_id AND l.status = 'ACTIVE'
     GROUP BY b.book_id, b.total_copies, b.available_copies
     ORDER BY b.book_id
  ) LOOP
    v_checked := v_checked + 1;
    IF r.available_copies <> r.total_copies - r.active_loans THEN
      add_error(r.book_id || ' available=' || r.available_copies
                || ' expected=' || (r.total_copies - r.active_loans));
    END IF;
  END LOOP;

  -- (2) 貸出状態と返却日の整合 : CASE 文
  FOR r IN (SELECT loan_id, status, returned_at FROM loans ORDER BY loan_id) LOOP
    CASE r.status
      WHEN 'ACTIVE' THEN
        IF r.returned_at IS NOT NULL THEN
          add_error('loan ' || r.loan_id || ' is ACTIVE but has returned_at');
        END IF;
      WHEN 'RETURNED' THEN
        IF r.returned_at IS NULL THEN
          add_error('loan ' || r.loan_id || ' is RETURNED but returned_at is null');
        END IF;
    END CASE;
  END LOOP;

  -- (3) 貸出上限
  FOR r IN (
    SELECT m.member_id, m.max_loans, COUNT(l.loan_id) AS active_loans
      FROM members m
      JOIN loans l ON l.member_id = m.member_id AND l.status = 'ACTIVE'
     GROUP BY m.member_id, m.max_loans
    HAVING COUNT(l.loan_id) > m.max_loans
  ) LOOP
    add_error(r.member_id || ' has ' || r.active_loans || ' loans (max ' || r.max_loans || ')');
  END LOOP;

  log_hook('books checked=' || v_checked || ', errors=' || v_errors);

  IF v_errors > 0 THEN
    RAISE_APPLICATION_ERROR(-20100, 'integrity check failed (' || v_errors || '): ' || v_detail);
  END IF;
END;
