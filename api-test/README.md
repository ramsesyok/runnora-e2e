# api-test：WebAPI テストセット

runnora-e2e の WebAPI（HTTP）テストセットです。リポジトリ全体の構成は [../README.md](../README.md) を参照してください。
コマンドはすべてこのフォルダ（`api-test/`）で実行します。

**runnora / oapi2wire / runnora-docgen** を組み合わせた API テストのフルセット検証用サンプルです。
OpenAPI を正本として、API のサンプル実装・モック・テスト・ドキュメントまでを一通りそろえています。
runnora の PL/SQL 前後処理では、API テストでよく使う構文（FOR LOOP、SAVEPOINT、カーソル、
BULK COLLECT/FORALL、例外処理、自律型トランザクションなど）を実際の Oracle で動かして確認しています。

| 成果物 | 場所 | 作り方 |
|---|---|---|
| API 仕様 (正本) | [openapi/library-api.yaml](openapi/library-api.yaml) | 手書き |
| API サンプル実装 | [api/](api/main.go)（Go + go-ora）、[db/](db/)（DDL） | 手書き |
| API モック | [mock/](mock/mock-cases.yaml) + [fixtures/responses/](fixtures/responses/) → `mock/wiremock-out/` | `oapi2wire init` の雛形を編集 → `oapi2wire build` |
| 生成テスト | [runbooks/generated/](runbooks/generated/), [cases/generated/](cases/generated/) | `runnora generate` |
| 契約テスト | [runbooks/contract/](runbooks/contract/), [cases/contract/](cases/contract/) | 生成 template を複製して拡張。期待本文はモックの戻り値と同じ `fixtures/responses/` を参照 |
| シナリオ試験 | [runbooks/scenarios/](runbooks/scenarios/), [sql/](sql/README.md) | 手書き（PL/SQL 前後処理付き） |
| API ドキュメント・テスト手順書 | [docs/design-doc.pdf](docs/design-doc.pdf)、`docs/_book/`（HTML） | `tools/openapi-doc` + `runnora-docgen` + `ddq` |

## 題材：図書貸出 API

蔵書・会員・貸出を Oracle で管理する 8 operation の API です（詳細は OpenAPI／手順書 第 2 章）。

| メソッド | パス | 概要 |
|---|---|---|
| GET | `/health` | 稼働確認（DB 疎通含む） |
| GET / POST | `/books` | 蔵書検索 / 登録 |
| GET | `/books/{bookId}` | 蔵書取得 |
| GET | `/members/{memberId}` | 会員と貸出状況（貸出中件数・延滞有無） |
| GET | `/members/{memberId}/loans` | 貸出履歴 |
| POST | `/loans` | 貸出（在庫切れ・上限・延滞・利用停止は 409） |
| POST | `/loans/{loanId}/return` | 返却（返却済みは 409） |

## 構成

```text
api-test/
├─ openapi/library-api.yaml      API 仕様（正本）
├─ api/                          サンプル実装（Go）        → 127.0.0.1:18081
├─ db/                           スキーマ DDL（SQL*Plus で実行）
├─ docker-compose.yml            Oracle Database Free 23ai → 127.0.0.1:1522/FREEPDB1
├─ mock/                         oapi2wire の case YAML → WireMock 127.0.0.1:18080
├─ fixtures/responses/           応答本文（モックの戻り値 = 契約テストの期待値。両方から参照）
├─ config.yaml                   runnora 設定（実 API 用。共通 PL/SQL フック）
├─ config.mock.yaml              runnora 設定（モック用。DB なし）
├─ sql/common/                   共通 前処理（リセット・シード）/ 後処理（不変条件検証）
├─ sql/cases/                    ケース固有の前処理・後処理
├─ runbooks/generated/           runnora generate の出力（再生成前提）
├─ runbooks/contract/            契約テスト suite + template（モック・実 API 両方で実行）
├─ runbooks/scenarios/           シナリオ試験 LIB-001〜007（実 API のみ）
├─ runbooks/demo/                事後検証が不整合を検知することの確認（exit 4 が期待値）
├─ cases/                        ケース JSON（generated / contract）
├─ tools/openapi-doc/            OpenAPI → 手順書 API 仕様章（.qmd）の変換
├─ tools/contract-check/         契約ケースとモックケースが同じ応答ファイルを指しているかの検査
├─ docs/                         手順書（ddq / Quarto book）。docs/generated/ は生成物
└─ scripts/                      実行スクリプト（PowerShell 5.1 / 7 両対応）
```

## 必要なもの

| ツール | 用途 | 既定の場所（環境変数で変更可） |
|---|---|---|
| Docker Desktop | Oracle Database Free | - |
| Go 1.24+ | API・openapi-doc のビルド | PATH |
| Java 17+ | WireMock | PATH |
| runnora | テスト実行 | `..\..\runnora\runnora.exe`（`RUNNORA_EXE`） |
| oapi2wire | モック生成 | `..\..\oapi2wire\oapi2wire.exe`（`OAPI2WIRE_EXE`） |
| runnora-docgen | 手順書の表生成 | `..\..\runnora-docgen\runnora-docgen.exe`（`RUNNORA_DOCGEN_EXE`） |
| WireMock jar | モックサーバ | `..\..\runnora\docs\tools\wiremock-standalone-3.13.2.jar`（`WIREMOCK_JAR`） |
| Quarto + ddq 2.4.0 | 手順書の HTML/PDF 発行 | PATH（`DDQ_EXE`） |

Oracle イメージ `container-registry.oracle.com/database/free:latest` を使います（未取得なら初回に pull）。
既存の `oracle-free` コンテナ（1521）と衝突しないよう、ホスト側は **1522** を使います。

## 実行

一括実行（Oracle 起動・スキーマ作成 → モック生成 → テスト雛形生成 → API/WireMock 起動
→ モック・実 API のテスト → 停止 → 手順書 HTML 生成）:

```powershell
./scripts/run-all.ps1              # 手順書は HTML のみ
./scripts/run-all.ps1 -DocFormat Both   # PDF も発行
```

個別実行:

```powershell
./scripts/db-up.ps1         # Oracle 起動 + LIBAPP スキーマ (再) 作成
./scripts/mock-build.ps1    # oapi2wire validate + build
./scripts/generate.ps1      # runnora generate (runbooks/generated を作り直す)
./scripts/api-start.ps1     # ターミナル A: API
./scripts/mock-start.ps1    # ターミナル B: WireMock
./scripts/test-mock.ps1     # モックに対して 生成 + 契約
./scripts/test-api.ps1      # 実 API に対して 生成 + 契約 + シナリオ + 検知確認 + カバレッジ
./scripts/build-docs.ps1 -Format Both
./scripts/db-down.ps1       # Oracle 停止・削除
```

runnora を直接呼ぶ例（シナリオ LIB-005）:

```powershell
..\..\runnora\runnora.exe run --config config.yaml `
  --before-sql sql/cases/lib005_savepoint_before.sql `
  --after-sql  sql/cases/lib005_assert_after.sql `
  runbooks/scenarios/lib-005-savepoint.yml
```

## テストの内容

| 種類 | 実行先 | 本数 | 検証 |
|---|---|---|---|
| 生成テスト | モック / 実 API | 8 suite | OpenAPI example で呼び出しステータスを確認 |
| 契約テスト | モック / 実 API | 8 suite・21 ケース | ステータス + **本文の全体一致（モックと共有する期待ファイル）** + **OpenAPI 応答スキーマ検証**（`openapi3` ランナー） |
| シナリオ試験 | 実 API | 7 runbook・59 手順 | 状態変化・ID 引き継ぎ・**DB 直接照会（runn DB ランナー）**・前後処理での DB 検証 |
| 検知確認 | 実 API | 1 | 事後検証が DB 不整合を検知して exit 4 |

| ID | シナリオ | 前処理 (PL/SQL) | 後処理 (PL/SQL) |
|---|---|---|---|
| LIB-001 | 貸出〜返却・二重返却 | - | SELECT INTO + 例外で事後条件検証 |
| LIB-002 | 在庫切れ（1 冊の取り合い） | - | - |
| LIB-003 | 延滞者の貸出拒否（応答から延滞中の貸出を探して返却・照会に引き継ぐ） | %ROWTYPE で延滞貸出を作成 | - |
| LIB-004 | 貸出上限（応答の貸出 ID を返却・照会に引き継ぐ） | 明示カーソル + WHILE LOOP | - |
| LIB-005 | SAVEPOINT による部分確定 | SAVEPOINT / ROLLBACK TO / EXCEPTION_INIT | 取消結果と自律型ログを検証 |
| LIB-006 | 異常系 400/404/409 | - | DB 不変（件数・採番）を検証 |
| LIB-007 | 大量履歴 | BULK COLLECT LIMIT + FORALL | - |

すべての runbook の前後で、共通フック（`00_reset` → `10_seed_master` / `90_verify_integrity`）が走ります。
`90_verify_integrity` は「貸出可能冊数 = 所蔵 − 貸出中」などの不変条件をカーソル FOR LOOP で検証し、
違反があれば `RAISE_APPLICATION_ERROR` で runnora を exit 4 にします。

API が参照しないテスト用ヘッダを付けて送っています（手順書の HTTP 呼び出し表の Headers 欄に出ます）。
契約テストは `X-Test-Case: <operationId>/<ケース名>`（ケース JSON の `headers`）、シナリオ試験は `X-Test-Scenario: <シナリオ ID>` です。

## モックの戻り値と期待値の共有

oapi2wire のモックは、runbook を書きながら動かして確かめる相手として使います。
そのためモックの戻り値と runbook の期待値を同じファイル（`fixtures/responses/<operationId>/<caseId>.json`）にしています。

```text
mock/mock-cases.yaml            - id: getMember_M0001 ... bodyFile: getMember/getMember_M0001.json
                                                                     │（oapi2wire --responses-root fixtures/responses）
fixtures/responses/getMember/getMember_M0001.json  ◀────────────────┤
                                                                     │（json://）
runbooks/contract/get_getMember.suite.yml
  M0001:
    include:
      vars:
        case:     json://../../cases/contract/members/get_getMember/01_M0001.json   ← 入力・ステータス・mockCase・ignorePaths
        expected: json://../../fixtures/responses/getMember/getMember_M0001.json
```

- 契約ケースとモックケースは 1 対 1（`expect.mockCase`）。組合せの誤りは `tools/contract-check` が `mock-build.ps1` の中で検出します。
- 本文は `compare` で全体一致。実装で変わる項目（貸出 ID・日付）だけ `ignorePaths`（jq 形式）で除外します。
- モックに流したときの本文比較は同じファイル同士なので、モックで確かめられるのは「正しいケースが選ばれること・ステータス・OpenAPI スキーマ」です。本文の正しさは実 API に流して確かめます。
- suite はケースごとに include ステップを並べ、`loop` は使いません（下表 #12）。
- この形の suite を手順書にするには、include の `vars` の `json://` を読む runnora-docgen が必要です（[ramsesyok/runnora-docgen#4](https://github.com/ramsesyok/runnora-docgen/pull/4) で main にマージ済み）。

## 検証結果（2026-09-26、Windows 11 / Windows PowerShell 5.1）

`./scripts/run-all.ps1` で次を確認しました。

- モック: 生成 8/8、契約 8/8 成功
- 実 API: 生成 8/8、契約 8/8、シナリオ 7/7 成功、検知確認は期待どおり exit 4
  （`ORA-20100: integrity check failed (1): B0001 available=2 expected=3`）
- OpenAPI カバレッジ（契約 + シナリオ）: 8/8 operation
- 手順書: HTML（`docs/_book/`）と PDF（`docs/design-doc.pdf`、116 ページ）を発行
- 期待値を 1 項目だけ誤らせた契約ケースが失敗すること（検証が空振りしていないこと）

## 作成中に分かったこと（ツールへのフィードバック）

| # | ツール | 内容 | 本サンプルでの対処 |
|---|---|---|---|
| 1 | runnora | `--report-format json` / `junit` が未実装で、指定してもテキストが出力される | text で保存 |
| 2 | runnora | フック SQL はファイル全体を 1 文で実行。SQL*Plus の `/` 終端は `PLS-00103` | 1 ファイル 1 無名ブロックで記述（[sql/README.md](sql/README.md)） |
| 3 | runnora | エラー終了時に cobra の Usage が毎回出力され、エラーが読みにくい | - |
| 4 | runnora (runn) | suite の `json://` 相対パスは include 先 template の位置で解決される | template を suite と同じディレクトリに配置 |
| 5 | runnora generate | requestBody の無い POST（returnLoan）にも `{"TODO": ...}` ボディを送る。クエリは全パラメータを空値でも付与 | 実装が余分なボディ・空クエリを無視するので実害なし |
| 6 | runnora (runn DB) | Oracle の NUMBER は文字列で返る | `== "14"` / `int(...)` で比較 |
| 7 | oapi2wire | mapping の `id` が build ごとにランダム UUID（README 例は caseId）で、生成物の差分が安定しない | `mock/wiremock-out/` を Git 管理外に |
| 8 | runnora-docgen | 前処理・後処理表で SQL の改行が失われ 1 段落になる（GridTable セル内） | runnora-docgen をファイル名のみ表示する方式に修正（[ramsesyok/runnora-docgen#3](https://github.com/ramsesyok/runnora-docgen/pull/3) で main にマージ済み）。SQL 全文は手順書の付録に掲載 |
| 9 | runnora-docgen | DB 照会ステップは SQL が表に出ず「検証のみ」になる | 手順書本文で補足 |
| 10 | ddq | PlantUML サーバを 127.0.0.1:18080 で探すため WireMock と衝突する | WireMock 停止後に手順書を生成 |
| 11 | go-ora | TZ なし `TIMESTAMP` と `SYSTIMESTAMP` の比較がセッション TZ 依存で、go-ora 接続では 9 時間ずれて失敗した | ログ列を `TIMESTAMP WITH TIME ZONE` に |
| 12 | runn | `loop`（`until` なし）は最後の回の失敗しか報告しない。`runnora generate` の suite（loop + include でケースを回す形）は、ケースを増やすと途中のケースの失敗を見逃す | 契約 suite はケースごとに include ステップを並べる形に変更。`contract-check` が loop の使用も検出 |
| 13 | runnora-docgen | HTTP 呼び出し表の Query 欄が常に空（runn はクエリを URL に書くが、docgen は `query` キーだけを見ていた）。表のセルで英数字の語が途中改行され、HTML に空白が入る（`tech_a vailable`） | runnora-docgen を修正（[ramsesyok/runnora-docgen#6](https://github.com/ramsesyok/runnora-docgen/pull/6) で main にマージ済み） |

OpenAPI 応答検証（`openapi3` ランナー）は、作成時に「`GET /books` 等が 400 を返すのに OpenAPI に未定義」
という仕様漏れを検出しました（OpenAPI を修正済み）。

## 注意

- DB のユーザー・パスワード（`libapp/libapp_pw`、SYS は `RunnoraE2e_Sys1`）はローカル検証専用です。
  runnora は DSN のテンプレート展開をしないため `config.yaml` に直書きしています。
- `db-up.ps1` は LIBAPP ユーザーを削除して作り直します（接続中のセッションは切断します）。
