# runnora シリーズ コマンドマニュアル（スクリプトを使わない手順）

`scripts/*.ps1` を使わずに、runnora シリーズのコマンドだけでテストの一連の流れを行う手順です。
コマンドは Windows の PowerShell で書いています（bash でもパスの区切りを `/` にすれば同じです）。
スクリプトが内部で何をしているかは [スクリプトの処理解説](scripts-explained.md) を参照してください。

## 0. 前提

### 0.1 用意するもの

| もの | 用途 | 入手 |
|---|---|---|
| `runnora` | テストの実行、テスト雛形の生成、検査、カバレッジ | [runnora の Releases](https://github.com/ramsesyok/runnora/releases) の `runnora_v<版>_windows_amd64.zip` |
| `runnora-migrate` | 旧形式（`config.yaml`）のプロジェクトの移行（必要な場合だけ） | 同じ zip に入っている |
| `oapi2wire` | OpenAPI と case YAML から WireMock のモックを生成 | [oapi2wire の Releases](https://github.com/ramsesyok/oapi2wire/releases) |
| `runnora-docgen` | runbook からテスト手順書の原稿（表）を生成 | [runnora-docgen の Releases](https://github.com/ramsesyok/runnora-docgen/releases) |
| Java と WireMock の jar | モックサーバ | Maven Central の `org.wiremock:wiremock-standalone`（3.13.2 で確認） |
| Docker | Oracle Database（実 API のテスト） | Docker Desktop など |
| Go | このサンプルの図書 API・gRPC サーバのビルド（テスト対象を自分で用意する場合は不要） | https://go.dev/dl/ |
| Quarto と ddq | 手順書の HTML / PDF 発行（必要な場合だけ） | ― |

zip を展開した実行ファイルを PATH の通ったフォルダに置き、版を確認します。

```powershell
runnora version
runnora-docgen --version
oapi2wire --version
```

### 0.2 フォルダと約束ごと

- コマンドは**テストセットのフォルダ**（`runnora.yaml` のあるフォルダ。`api-test/` や `grpc-test/`）で実行します。runnora と runnora-docgen はカレントディレクトリから親へ `runnora.yaml` を探します（別の場所なら `--project`）。
- テストの中身は `runnora.yaml`（環境・スイート・共通の前後処理）と、各 runbook の `runnora:` ブロック（シナリオ ID・固有の前後処理・期待する結果）に書きます。コマンドには**スイート名か runbook を渡すだけ**です。
- 実行結果は runnora が `reports/<日時>-<スイート名>/` に保存します（`summary.html`・`report.json`・`evidence/`）。

## 1. ワークフロー全体

```mermaid
flowchart LR
  subgraph 準備
    A[OpenAPI] --> B[モック生成<br>oapi2wire]
    A --> C[テスト雛形生成<br>runnora generate]
  end
  B --> D[モックで実行<br>runnora run]
  C --> D
  D --> E[実環境を用意<br>DB・API]
  E --> F[実環境で実行<br>runnora run]
  F --> G[結果の確認<br>summary.html]
  F --> H[カバレッジ<br>runnora coverage]
  C --> I[手順書の原稿<br>runnora-docgen]
  I --> J[手順書の発行<br>ddq]
```

| 段階 | 目的 | 主なコマンド |
|---|---|---|
| 2 | プロジェクトを用意・検査する | `runnora init`、`runnora validate`、`runnora list` |
| 3 | モックを作って起動する | `oapi2wire validate` / `build`、`java -jar wiremock…` |
| 4 | OpenAPI からテスト雛形を作る | `runnora generate` |
| 5 | モックに対してテストする | `runnora run --suite generated-mock` など |
| 6 | 実環境（DB・API）を用意する | `docker compose up`、`sqlplus`、API の起動 |
| 7 | 実環境に対してテストする | `runnora run --suite scenarios` など |
| 8 | 結果を確認する | `summary.html`、`report.json`、`evidence/` |
| 9 | カバレッジを確認する | `runnora coverage` |
| 10 | 手順書を作る | `runnora-docgen generate`、`ddq` |
| 11 | gRPC のテスト | `runnora run --suite grpc` |
| 12 | 片付ける | `docker compose down` |

以下、`api-test/` を例に進めます（gRPC は 11 章）。

## 2. プロジェクトを用意する・検査する

新しいプロジェクトでは `runnora.yaml` の雛形を作ります（このサンプルには既にあります）。

```powershell
runnora init                                   # runnora.yaml の雛形 (環境・スイート・証跡の設定例)
runnora init --dsn "oracle://user:pass@host:1521/SERVICE"   # Oracle の前後処理を使う場合
```

旧形式（`config.yaml`・`--config`・`--before-sql`）のプロジェクトは移行します。

```powershell
runnora-migrate .              # 変更の予定と TODO を表示するだけ (dry-run)
runnora-migrate --write .      # 書き込む (Git の未コミットの変更がないこと)
```

実行する前に、設定と runbook を検査します。実行はしません。

```powershell
runnora validate               # runnora.yaml と全 runbook の検査 (既定の環境 = defaults.env)
runnora validate --env mock    # 環境 mock の変数で展開して検査
runnora list -l 'runbooks/**/*.yml'   # runbook とシナリオ ID、それを選ぶスイートの一覧
```

## 3. モックを作って起動する

OpenAPI（`openapi/library-api.yaml`）と、返し分けの条件を書いた case YAML（`mock/mock-cases.yaml`）、応答本文（`fixtures/responses/`）から WireMock の資産を作ります。

```powershell
# 整合性の検査 (不整合があれば終了コード 1)
oapi2wire validate --openapi openapi/library-api.yaml --cases mock/mock-cases.yaml --responses-root fixtures/responses

# WireMock の mappings/ と __files/ を作り直す
oapi2wire build --openapi openapi/library-api.yaml --cases mock/mock-cases.yaml --responses-root fixtures/responses `
  --out mock/wiremock-out --clean --fail-on-missing-operation --fail-on-missing-body-file
```

新しい API で case YAML がまだない場合は、雛形を作ってから編集します。

```powershell
oapi2wire init --openapi openapi/library-api.yaml --out-cases mock/mock-cases.yaml --responses-root fixtures/responses
```

WireMock を**別のターミナル**で起動します（Ctrl+C で終了）。

```powershell
java -jar C:\tools\wiremock-standalone-3.13.2.jar --port 18080 --bind-address 127.0.0.1 `
  --root-dir mock/wiremock-out --disable-banner
```

起動の確認：`Invoke-WebRequest http://127.0.0.1:18080/health`

## 4. OpenAPI からテスト雛形を作る

```powershell
runnora generate --openapi openapi/library-api.yaml --clean --force
```

- operation ごとに `runbooks/generated/<タグ>/<メソッド>_<operationId>.template.yml`（1 回の呼び出し）と `.suite.yml`（ケースを順に流す）、`cases/generated/.../default.json`（入力と期待するステータス）を作ります。
- 接続先は `${RUNNORA_BASE_URL}` で、実行時に環境（`unit` / `mock`）の `vars` から決まります。
- `runbooks/generated/` は作り直すたびに上書きされます。手を加えて育てるテストは `runbooks/contract/` などに複製します。
- 一部だけ作る：`--tags books,loans`、`--operation-ids getBook,listBooks`

## 5. モックに対してテストする

```powershell
runnora run --suite generated-mock     # 生成テスト (example 値とステータス)
runnora run --suite contract-mock      # 契約テスト (ステータス・本文・OpenAPI の応答スキーマ)
```

- スイートに `env: mock` とあるので、接続先は WireMock になります（`--env` は不要）。
- 画面には結果の要約と、最後に `レポート: reports/<日時>-<スイート名>/summary.html` が表示されます。
- 終了コードは、すべて期待どおりなら 0、そうでなければ 1 です（15 章）。

## 6. 実環境（DB・API）を用意する

### 6.1 Oracle を起動してスキーマを作る

```powershell
docker compose up -d oracle

# healthy になるまで待つ (数分かかる。starting の間は待つ)
docker inspect -f '{{.State.Health.Status}}' runnora-e2e-oracle

# LIBAPP ユーザーとテーブルを作る (何度実行しても「定義のみ・データなし」になる)
docker exec runnora-e2e-oracle sqlplus -s -L '/ as sysdba' '@/opt/runnora-e2e/db/01_create_user.sql'
docker exec runnora-e2e-oracle sqlplus -s -L 'libapp/libapp_pw@//localhost:1521/FREEPDB1' '@/opt/runnora-e2e/db/02_schema.sql'
```

データはテストの実行時に、runnora が前処理 SQL（`sql/common/*.sql` など）で入れます。

### 6.2 図書 API を起動する

**別のターミナル**で起動します（Ctrl+C で終了）。

```powershell
go build -C api -o ../bin/library-api.exe .
.\bin\library-api.exe          # 待ち受け 127.0.0.1:18081。DB は LIBAPI_DSN (既定 oracle://libapp:libapp_pw@127.0.0.1:1522/FREEPDB1)
```

起動の確認：`Invoke-WebRequest http://127.0.0.1:18081/health`

## 7. 実環境に対してテストする

```powershell
runnora run --suite generated-unit     # 生成テスト (前処理に contract_setup.sql を追加)
runnora run --suite contract-unit      # 契約テスト (同上)
runnora run --suite scenarios          # シナリオ試験 LIB-001〜007 と検知デモ
```

runbook ごとに、次の順で前後処理 SQL が流れます（すべて `runnora.yaml` と `runnora:` ブロックの指定どおり）。

```text
環境の before → スイートの before → runbook の before → runbook の本体 → runbook の after → 環境の after
```

よく使う実行のしかた：

```powershell
runnora run runbooks/scenarios/lib-005-savepoint.yml        # 1 本だけ (前後処理は runnora: ブロックから)
runnora run --env mock runbooks/contract/get_getBook.suite.yml   # 環境を指定して 1 本
runnora run --suite scenarios --var API_URL=http://127.0.0.1:28081   # 変数を一時的に上書き
runnora run --suite scenarios --fail-fast                   # 最初の失敗で止める
runnora run --suite scenarios --report-format junit         # JUnit 形式 (report.xml) も出す (CI 向け)
runnora run --suite scenarios --no-evidence                 # 証跡を保存しない
runnora run --suite scenarios --trace                       # runn のトレースを出す (調査用)
```

変数の値は、`runnora.yaml` の `vars` → OS の環境変数 → `--var` の順に後のものが優先されます。
Oracle のパスワードは `runnora.yaml` の `${LIBAPP_PASSWORD:-libapp_pw}` なので、`$env:LIBAPP_PASSWORD = '...'` で変えられます。

## 8. 結果を確認する

実行ごとに次のフォルダができます（同じ秒に同じスイートを流すと `-2`、`-3` … が付きます）。

```text
reports/20260927-153012-scenarios/
├─ summary.html                  サマリー HTML (ブラウザで開く)
├─ report.json                   ステップ単位の結果 (機械処理用)
├─ report.xml                    --report-format junit のときだけ
└─ evidence/
   └─ LIB-001/                   シナリオ ID ごと
      ├─ 01-member_before.json   <ステップの番号>-<ステップのキー>.json (応答)
      ├─ 15-member_loans[2].json loop の回ごと
      └─ 08-inspect_book.call.json  include 先のステップ
```

- **summary.html**
  - 実行の情報、集計、runbook の一覧（不合格を先頭に・不合格だけ表示の切り替え）を載せます。
  - runbook を開くと、前後処理とステップの表（失敗メッセージ、`diffEps()` の差分、証跡へのリンク）が見られます。
  - 印刷すると全部開いた状態になります。
- **証跡**
  - HTTP・gRPC・DB・exec の各ステップの応答を runnora が自動で保存します（runbook に `dump` は書きません）。
  - `Authorization`・`Cookie` などは `***` に置き換えます。
  - リクエストも残すには、`runnora.yaml` に `evidence.mode: full` を書きます。
- **report.json**
  - 手順書の `manifest.json`（`scenarioId`・`steps[].key`）と、シナリオ ID とステップのキーで突き合わせられます。

```powershell
# 最新の実行フォルダの summary.html を開く
$run = Get-ChildItem reports -Directory | Sort-Object CreationTime | Select-Object -Last 1
Start-Process (Join-Path $run.FullName 'summary.html')

# 期待どおりでなかった runbook と、失敗したステップを一覧にする
$r = Get-Content (Join-Path $run.FullName 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$r.results | Where-Object { -not $_.passed } | ForEach-Object {
  $_.id; $_.steps | Where-Object result -eq 'failure' | ForEach-Object { "  $($_.key): $($_.error)" }
}
```

## 9. カバレッジを確認する

```powershell
# OpenAPI の operation のうち、契約テストとシナリオで呼んだもの
runnora coverage --long 'runbooks/contract/*.template.yml' 'runbooks/scenarios/*.yml' 'runbooks/demo/*.yml'

# スイート単位で (gRPC は proto の RPC ごと)
runnora coverage --long --suite grpc
```

生成テストの suite は、loop で template を include するため runn の集計対象になりません。そのため、上の例では template を直接数えています。

## 10. 手順書を作る

runbook と `runnora.yaml` から、手順書の表（Quarto の `.qmd`）を作ります。前後処理は `runnora run` と同じ順で載ります。

```powershell
runnora-docgen generate --suite contract-unit --out docs/generated/contract --force
runnora-docgen generate --suite scenarios --out docs/generated/scenarios --force
runnora-docgen generate --env unit --out docs/generated/one --force runbooks/scenarios/lib-001-loan-lifecycle.yml   # 1 本だけ
```

- シナリオごとのフォルダに `scenario.qmd`（手順表）、`http.qmd`、`expectations.qmd`、`before.qmd` / `after.qmd`、`manifest.json` ができます。
- 手順書の章（`docs/chapters/`）からこれらを `{{< include >}}` で読み込み、`ddq html docs`（PDF は `ddq pdf docs`）で発行します。
- このサンプルの章立てに合わせた取り込み原稿（`_body.qmd`）の組み立てと、API 仕様・SQL 付録の原稿は、`scripts/build-docs.ps1` が行っています（手順書の構成に依存する部分のため）。

## 11. gRPC のテスト（grpc-test/）

`grpc-test/` で実行します。DB は使いません。

```powershell
# gRPC サーバを別のターミナルで起動 (待ち受け 127.0.0.1:19090)
go run ./cmd/libraryd -proto proto/library.proto

# テストとカバレッジ
runnora validate
runnora run --suite grpc                  # 4 本 (Unary / Server streaming / 計算 streaming / 系列分析)
runnora run runbooks/series-analysis.yml  # 1 本だけ
runnora coverage --long --suite grpc

# 手順書の原稿 (RPC 種別の判定に proto を渡す)
runnora-docgen generate --suite grpc --proto proto/library.proto --out docs/generated --force
```

系列分析は、`diffEps(期待, 実際, 許容誤差の設定)` で数値の許容誤差付きに比較します（runnora-diff と同じ比較処理。runnora-diff の実行ファイルは不要です）。
差分の全件は証跡の `<番号>-<キー>.diff.json` に保存されます。

## 12. 片付け

```powershell
# API・WireMock・gRPC サーバ：起動したターミナルで Ctrl+C
docker compose down            # Oracle のコンテナを停止・削除 (データも消える)
Remove-Item -Recurse reports   # 実行結果を消す場合
```

## 13. コマンド早見表

| やりたいこと | コマンド |
|---|---|
| 版を確認する | `runnora version` / `runnora-docgen --version` / `oapi2wire --version` |
| runnora.yaml の雛形を作る | `runnora init` |
| 旧形式から移行する | `runnora-migrate .` → `runnora-migrate --write .` |
| 設定と runbook を検査する | `runnora validate [--env <環境>]` |
| runbook とスイートの一覧 | `runnora list -l '<runbook のパターン>'` |
| モックの整合性を検査する | `oapi2wire validate --openapi <OpenAPI> --cases <case YAML> --responses-root <応答>` |
| モックを作る | `oapi2wire build --openapi <OpenAPI> --cases <case YAML> --responses-root <応答> --out <出力> --clean` |
| case YAML の雛形を作る | `oapi2wire init --openapi <OpenAPI> --out-cases <case YAML> --responses-root <応答>` |
| テスト雛形を作る | `runnora generate --openapi <OpenAPI> --clean --force` |
| スイートを実行する | `runnora run --suite <スイート>` |
| runbook を 1 本実行する | `runnora run [--env <環境>] <runbook>` |
| 変数を上書きして実行する | `runnora run --suite <スイート> --var NAME=VALUE` |
| JUnit でも出す | `runnora run --suite <スイート> --report-format junit` |
| カバレッジ | `runnora coverage --long --suite <スイート>` または `runnora coverage --long <runbook のパターン>` |
| 手順書の原稿を作る | `runnora-docgen generate --suite <スイート> --out <出力> --force [--proto <proto>]` |

このサンプルのスイート：

| テストセット | スイート | 環境 | 内容 |
|---|---|---|---|
| api-test | `generated-mock` | mock | 生成テスト 8 本 |
| api-test | `contract-mock` | mock | 契約テスト 8 本 |
| api-test | `generated-unit` | unit | 生成テスト 8 本（実 API） |
| api-test | `contract-unit` | unit | 契約テスト 8 本（実 API） |
| api-test | `scenarios` | unit | シナリオ試験 LIB-001〜007 と検知デモ |
| grpc-test | `grpc` | unit | gRPC 4 本 |

## 14. runnora.yaml の主な設定

```yaml
version: 2
defaults:
  env: unit                        # --env を省略したときの環境
environments:
  unit:
    vars:                          # runbook の ${API_URL} などに入る値
      API_URL: "http://127.0.0.1:18081"
    oracle:
      dsn: "${ORACLE_DSN}"         # 前後処理 SQL の接続先
    hooks:                         # 全 runbook に共通の前後処理
      before: [sql/common/00_reset.sql]
      after: [sql/common/90_verify_integrity.sql]
suites:
  scenarios:
    env: unit
    select:
      paths: [runbooks/scenarios/*.yml]
    hooks:                         # このスイートだけの前後処理 (環境の hooks の内側)
      before: []
report:
  dir: reports                     # 実行ごとのフォルダを作る場所 (既定 reports)
evidence:
  mode: response                   # response (既定。応答だけ) / full (リクエストも)。保存しないときは run --no-evidence
  mask:
    headers: [X-Api-Key]           # 追加で *** にするヘッダ
    paths: [.password]             # 本文で *** にする値 (jq のパス)
```

runbook 側の `runnora:` ブロック：

```yaml
runnora:
  id: LIB-003                      # シナリオ ID (レポート・証跡・手順書で共通)
  before: [sql/cases/lib003_overdue_before.sql]
  after: []
  expect: pass                     # pass (既定) / fail / hookFail
```

## 15. 終了コード

| コード | 意味 |
|---|---|
| 0 | すべて期待どおり（`expect: fail` / `hookFail` の runbook が期待どおりに失敗した場合を含む） |
| 1 | 期待どおりでない runbook がある |
| 2 | 設定・引数の誤り（未定義の変数、旧形式の設定を含む） |
| 3 | DB 接続の失敗 |
| 4 | 期待どおりでない runbook のうち、実際の結果が前後処理の失敗のものがある |
| 5 | レポートの出力の失敗 |

## 16. 困ったとき

| 症状 | 確認すること |
|---|---|
| `runnora.yaml が見つかりません` | テストセットのフォルダで実行しているか。別の場所なら `--project <パス>` |
| 終了コード 2（未定義の変数） | `runnora validate --env <環境>` で、どの変数が未定義かを確認する |
| 終了コード 3（DB 接続） | Oracle が `healthy` か（`docker inspect`）、ポート 1522、`LIBAPP_PASSWORD` |
| 接続できない（connection refused） | API（18081）・WireMock（18080）・gRPC サーバ（19090）が起動しているか |
| モックが 404 を返す | `oapi2wire build` をやり直したか、WireMock の `--root-dir` が `mock/wiremock-out` か |
| `dump ステップは…重複しています` の警告 | 旧来の `dump` ステップ。`runnora-migrate --write .` で削除できる（`generated/` は `runnora generate` で作り直す） |
| どのステップが失敗したか知りたい | `summary.html` で不合格の runbook を開く。応答は証跡のリンクから見られる |
