-- =============================================================
-- cases/demo_break_invariant_after.sql  (--after-sql : 検知デモ専用)
-- わざと在庫数を 1 減らして不変条件を壊す。
-- --after-sql は common.after より先に実行されるので、
-- 直後の common/90_verify_integrity.sql が不整合を検知して exit 4 になることを確認できる。
-- 通常のテストでは使わない (scripts/test-api.ps1 の「検知確認」でのみ使用)。
-- =============================================================
BEGIN
  UPDATE books SET available_copies = available_copies - 1 WHERE book_id = 'B0001';
  COMMIT;
END;
