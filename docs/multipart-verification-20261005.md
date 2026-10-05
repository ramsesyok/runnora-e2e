# LIB-008 multipart 実行確認（2026-10-05）

Windows / Go 1.27.1 上で、既存の Oracle E2E コンテナと現行の Go API を使い、変更していない `api-test/runbooks/scenarios/lib-008-cover-upload.yml` を実行した。

## 実行対象と結果

| 実行ファイル | 版 | 結果 |
|---|---|---|
| `api-test/bin/runnora-current.exe` | 現行ソース `64bf85163deb03b86c3cf8483c436211c01ca4fb` をビルド。表示版 `dev-64bf851`、runn v1.9.2 | exit 0、LIB-008 成功 |
| 隣接リポジトリの `runnora/runnora.exe` | 既存ファイル。表示版 `dev`、commit/build 情報は unknown | exit 0、LIB-008 成功 |

現行ソースは隣接リポジトリのチェックアウトを使用した。依存関係は既存の `go.work` に従う。既存実行ファイルは上書きしていない。

## 確認内容

正常系2件・異常系4件の HTTP 呼び出しと各結果の検証、計12ステップが成功した。

| ケース | HTTP 結果 |
|---|---|
| PNG + 日本語 caption + primary="true" | 201。cover.png / image/png / 93 bytes、SHA-256、caption、primary が期待値と一致 |
| 画像だけ、任意項目省略 | 201。caption は空、primary は false |
| 画像ではないファイル | 400、image must be PNG or JPEG |
| image 項目なし | 400、image is required |
| primary="yes" | 400、primary must be boolean |
| 存在しない本 B9999 | 404、NOT_FOUND |

PNG の SHA-256 は `cd4e1d7819e60197b5fa92001c60352cd755f1c6d08a351e15362f9119aaa1ed`。送信ファイルの実際のハッシュとも一致した。OpenAPI 応答検証、共通前処理 `00_reset.sql`・`10_seed_master.sql`、後処理 `90_verify_integrity.sql` も成功した。

## 再実行

API と Oracle を起動し、`api-test/` で実行する。

```powershell
& ./bin/runnora-current.exe run runbooks/scenarios/lib-008-cover-upload.yml
```

既定の unit 環境を使用する。フックで E2E 用 LIBAPP のテストデータが初期化される。

## ローカル証跡

- 現行ビルド: `api-test/reports/20261005-145646-run/`（report.json、summary.html、evidence/LIB-008/*.json）
- 既存実行ファイル: `api-test/reports/20261005-145703-run/`
- 実行ログと明示出力した JSON: `api-test/reports/multipart-current/`

reports と bin は Git 管理外のため、別のチェックアウトでは上記証跡は存在しない。

初回は Oracle 未起動のため前処理で失敗した。その後、Docker Desktop の起動を妨げる古い接続ファイル2件を含む `AppData/Local/Docker/run` を `run.e2e-backup-20261005` に退避し、Docker と既存 E2E Oracle コンテナを起動して再実行した。コンテナの作り直し・スキーマ再作成は行っていない。

この初期確認では LIB-008 の画像と文字列フォーム項目のアップロードに不具合は再現しなかった。
JSON パートを DTO として受け取る Spring Boot API は、この確認の対象に含めていない。
その後の JSON + CSV / PNG の 415 再現・修正・CI 検証は [multipart テスト](../multipart-test/README.md)を参照。
全 E2E スイートの再検証は、この初期確認の対象に含めていない。
