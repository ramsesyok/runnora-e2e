# SQL/PLSQL フック

runnora はフックファイルの **内容全体を 1 文として** go-ora の `ExecContext` に渡します。
そのため次の書式を守ります（作成時に実機で確認済み）。

| 書き方 | 可否 | 確認結果 |
|---|---|---|
| 1 ファイル = 1 つの無名ブロック（`DECLARE ... BEGIN ... END;`） | ○ | 複数の DML/DDL はブロック内にまとめる |
| 先頭・行末の `--` コメント、日本語コメント | ○ | |
| SQL*Plus の `/` 終端 | × | `PLS-00103: Encountered the symbol "/"` で exit 4 |
| DDL（`ALTER SEQUENCE` 等） | ○ | `EXECUTE IMMEDIATE` で実行する。暗黙コミットに注意 |
| ブロック内の局所ファンクションを SQL 文から呼ぶ | × | `PLS-00231`。変数に代入してから使う |
| `TIMESTAMP`（TZ なし）列と `SYSTIMESTAMP` の比較 | △ | 比較は TZ なし側をセッション TZで解釈するため（go-ora 接続で 9 時間ずれて失敗した）環境依存。`TIMESTAMP WITH TIME ZONE` を使う |
| ファイルをまたぐ SAVEPOINT・トランザクション | × | ファイルごとに接続プールから実行されるため、各ファイル内で完結させる |
| `RAISE_APPLICATION_ERROR` | ○ | runnora は exit 4（フック失敗）で終了する。事後条件のアサーションに使える |

フックは runbook 1 本ごとに `before → runbook → after` の順で実行されます
（suite の `include` + `loop` でも 1 回だけ）。after は before や runbook が失敗しても実行されます。

## 実行順序

```
before: config.yaml の common.before → --before-sql
after : --after-sql → config.yaml の common.after
```

## ファイル一覧と使っている PL/SQL 構文

| ファイル | 役割 | 主な構文 |
|---|---|---|
| common/00_reset.sql | 全データ削除・採番リセット | VARRAY, 数値 FOR LOOP, EXECUTE IMMEDIATE (DML/DDL), SQL%ROWCOUNT, DBMS_ASSERT, 局所プロシージャ + PRAGMA AUTONOMOUS_TRANSACTION |
| common/10_seed_master.sql | マスタ投入 | MERGE, レコード型 + 連想配列 (INDEX BY), 修飾式, 数値 FOR LOOP, CASE 式, 局所ファンクション |
| common/90_verify_integrity.sql | 事後の不変条件検証 | カーソル FOR LOOP, CASE 文, 局所プロシージャ, RAISE_APPLICATION_ERROR |
| cases/contract_setup.sql | 契約テスト用の貸出 2 件 | SELECT ... FOR UPDATE, RETURNING INTO, OUT パラメータ付き局所プロシージャ |
| cases/lib001_assert_after.sql | LIB-001 の事後条件 | SELECT INTO, NO_DATA_FOUND / TOO_MANY_ROWS, ユーザー定義例外 |
| cases/lib003_overdue_before.sql | 延滞貸出の作成 | %ROWTYPE, レコード単位 INSERT, 日付演算, RETURNING INTO |
| cases/lib004_fill_loans_before.sql | 貸出上限まで借りた状態 | パラメータ付き明示カーソル (OPEN/FETCH/CLOSE, FOR UPDATE, WHERE CURRENT OF), WHILE LOOP, %NOTFOUND/%ISOPEN |
| cases/lib005_savepoint_before.sql | 一部だけ確定する初期データ | SAVEPOINT / ROLLBACK TO SAVEPOINT, DUP_VAL_ON_INDEX, PRAGMA EXCEPTION_INIT, ネストしたブロック |
| cases/lib005_assert_after.sql | LIB-005 の事後条件 | 条件付き COUNT, RAISE_APPLICATION_ERROR |
| cases/lib006_assert_no_loans_after.sql | 異常系で DB が変わっていないこと | SELECT INTO, USER_SEQUENCES, IF ... ELSIF |
| cases/lib007_history_before.sql | 大量の貸出履歴 | BULK COLLECT ... LIMIT, FORALL, SQL%BULK_ROWCOUNT, 入れ子表 |
| cases/demo_break_invariant_after.sql | 検知デモ用に不整合を作る | （common/90 が exit 4 で検知することを確認） |
