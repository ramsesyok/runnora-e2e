-- =============================================================
-- cases/demo_break_invariant_after.sql  (DEMO-HOOK-FAILURE の runnora: ブロックの after : 検知デモ専用)
-- わざと在庫数を 1 減らして不変条件を壊す。
-- runbook の after は環境共通の後処理 (runnora.yaml の hooks.after) より先に実行されるので、
-- 直後の common/90_verify_integrity.sql が不整合を検知してフック失敗になることを確認できる (runbook は expect: hookFail)。
-- 通常のテストでは使わない (scripts/test-api.ps1 の「検知確認」でのみ使用)。
-- =============================================================
BEGIN
  UPDATE books SET available_copies = available_copies - 1 WHERE book_id = 'B0001';
  COMMIT;
END;
