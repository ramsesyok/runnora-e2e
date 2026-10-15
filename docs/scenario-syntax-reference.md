# runn / runnora テストシナリオ記法リファレンス

この文書は、ローカル LLM に単独で添付して runbook の読み方・書き方を質問できるようにまとめたものです。対象は、このリポジトリが使う **runn v1.9.2** と **runnora の format v2（`runnora.yaml`）** です。確認日: 2026-10-16。runn の全機能を列挙する仕様書ではなく、このリポジトリでシナリオを書くときに必要な記法を中心にしています。

## LLM に渡すときの前提

- `runnora.yaml` はプロジェクト全体の環境・スイート・SQL フック・レポート設定、各 `.yml` / `.yaml` runbook は操作と検証を記述する。
- runbook の `desc`、`labels`、`runners`、`vars`、`steps` は **runn** の記法。トップレベルの `runnora:` だけが **runnora 固有**のメタデータ。
- 質問への回答では、使うファイル、キーの階層、相対パスの基準を示し、実際の YAML 例を出す。ここにないキーを推測で作らない。対象バージョンやプロジェクト固有の設定が不明なら確認する。
- 実行可能な例にするには、接続先 API / gRPC サーバ、SQL、JSON、proto などの実ファイルが必要。以下の短い断片は、示した機能だけを説明する。

## 1. 最小構成と責務

```text
api-test/
├─ runnora.yaml                 # runnora: 環境、スイート、共通設定
├─ runbooks/
│  ├─ scenarios/example.yml    # runn: 手順 + runnora: シナリオ情報
│  └─ contract/template.yml    # include 用部品。runnora: は不要
├─ cases/                      # 入力と期待値の JSON
└─ sql/                        # runnora の前後処理 SQL
```

1 本の runbook は、上から順に実行する `steps` で構成されます。`steps` は名前付きマップでも配列でも書けます。このリポジトリでは、後から `steps.<名前>` で参照しやすい名前付きマップを主に使います。スイートは複数の runbook を選ぶ仕組みです。ケース JSON は繰り返し使う入力・期待値を外出ししたファイルで、必須ではありません。

### まず動く形

プロジェクト側（`runnora.yaml`）:

```yaml
version: 2
project:
  name: sample-api
defaults:
  env: local
environments:
  local:
    vars:
      API_URL: http://127.0.0.1:18081
suites:
  smoke:
    env: local
    select:
      paths: [runbooks/smoke/*.yml]
report:
  format: text
```

runbook 側（`runbooks/smoke/health.yml`）:

```yaml
desc: API の稼働確認
runnora:
  id: HEALTH-001
labels: [smoke]
runners:
  req:
    endpoint: ${API_URL}
steps:
  get_health:
    desc: ヘルスチェックを呼ぶ
    req:
      /health:
        get:
          body: null
    test: current.res.status == 200
  check_body:
    test: steps.get_health.res.body.status == "UP"
```

`runnora run --suite smoke` でスイートを、`runnora run runbooks/smoke/health.yml` で 1 本を実行します。後者でも `runnora:` は有効ですが、スイート専用の設定は適用されません。

配列形式の `steps` も使えます。その場合は `steps[0]`、`steps[1]` のように番号で参照します。マップ形式なら `steps.get_health` のように名前で参照します。

## 2. `runnora.yaml`：プロジェクトの設定

`version: 2` が現行形式です。`runnora.yaml` はカレントディレクトリから親へ検索され、別の場所のファイルは `--project <パス>` で指定します。

| キー | 意味 |
|---|---|
| `project.name` | レポートなどに表示するプロジェクト名 |
| `defaults.env` | 環境指定を省略した場合の環境名 |
| `environments.<名前>.description` | 環境の説明 |
| `environments.<名前>.vars` | `${NAME}` に渡す文字列変数 |
| `environments.<名前>.oracle` | SQL フック用 Oracle 接続。`dsn`、`max_open_conns`、`max_idle_conns`、`conn_max_lifetime_sec` |
| `environments.<名前>.hooks.before / after` | その環境で実行する全 runbook の前後 SQL |
| `environments.<名前>.backends` | `mode: stub / mock / real` と `note`。宣言・記録用で、サービスは自動起動しない |
| `suites.<名前>.env` | スイートが使う環境 |
| `suites.<名前>.select.paths` | runbook の glob。`**` で階層をまたげる。必須 |
| `suites.<名前>.select.labels` | いずれかのラベルを持つ runbook に絞る |
| `suites.<名前>.select.ids` | 指定 ID だけを、書いた順に実行する |
| `suites.<名前>.vars` | 環境変数の値をスイート単位で上書きする |
| `suites.<名前>.hooks.before / after` | スイート実行時だけ追加する SQL |
| `runn.scopes / trace` | runn の追加権限・トレース |
| `report.format / output / dir` | レポートの表示形式、出力先、実行ごとの保存先 |
| `evidence.mode` | `response`（既定）または `full`（リクエストも保存） |
| `evidence.mask.headers / paths` | 証跡で追加して伏せるヘッダーと JSON パス |
| `generate.*` | OpenAPI からの雛形生成の既定値 |

スイートが選ぶのは、`select.paths` に一致し、**トップレベルの `runnora:` を持つ** runbook だけです。include 用 template は通常 `runnora:` を書きません。直接ファイルを指定した場合は、`runnora:` のない runbook も実行できます。`select.ids` に見つからない ID がある場合、同一スイート内で ID が重複する場合はエラーです。

`suites.<名前>.env` と CLI の `--env` を両方指定して異なる値にした場合はエラーです。環境名は `suites.<名前>.env`、`--env`、`defaults.env`、単一環境の自動選択の順で決まります。

### 変数の優先順位

高い順に `--var NAME=VALUE` → OS の環境変数 → スイートの `vars` → 環境の `vars` です。プロジェクトの `vars` に書く値は文字列です。`${NAME}` と `${NAME:-既定値}` を使えます。未定義で既定値のない変数は実行前のエラーになります。パスワードはファイルに直接書かず OS の環境変数から渡します。

```yaml
environments:
  unit:
    vars:
      API_URL: http://127.0.0.1:18081
      ORACLE_DSN: oracle://libapp:${LIBAPP_PASSWORD}@127.0.0.1:1522/FREEPDB1
    oracle:
      dsn: ${ORACLE_DSN}
    hooks:
      before: [sql/common/00_reset.sql]
      after: [sql/common/90_verify_integrity.sql]
```

`runnora.yaml` の `vars` の値にある `${...}` は、OS 環境変数か `--var` で展開します。**同じ `vars` マップの別キーを使う展開ではありません。** 一方、`oracle.dsn`、`hooks` などでは組み立て済みの変数表を参照できます。runbook 内の `${...}` は runn が YAML 解析前に環境変数として展開します。

## 3. runbook のトップレベル

| キー | 提供元 | 意味 |
|---|---|---|
| `desc` | runn | runbook 全体の説明 |
| `labels` | runn | 検索・選択に使うラベルの配列 |
| `runners` | runn | `req`（HTTP）、`greq`（gRPC）、`db` など、ステップで使う接続定義 |
| `vars` | runn | runbook 内の入力値・期待値。スカラー、配列、オブジェクト、`json://...` などを置ける |
| `steps` | runn | 順番に実行する操作・検証 |
| `secrets` | runn | runbook のログで伏せる変数・値の指定 |
| `runnora` | runnora | ID、固有の SQL フック、期待するテスト結果、許可環境 |

`runnora:` ブロックの記法:

```yaml
runnora:
  id: LIB-004
  before: [sql/cases/lib004_fill_loans_before.sql]
  after: []
  expect: pass
  envs: [unit, integration]
```

| キー | 規則 |
|---|---|
| `id` | `runnora:` を書くなら必須。英数字、`-`、`_`、`.` のみ。プロジェクト内で一意にする |
| `before / after` | その runbook 固有の SQL ファイル。プロジェクトルート基準 |
| `expect` | `pass`（既定）、`fail`、`hookFail` のどれか。**runbook 全体の実行結果**の期待値 |
| `envs` | 実行を許す環境名。省略時は全環境。対象外なら SKIP |

**HTTP 404 や 400 を期待する正常な異常系テストは通常 `expect: pass` のままです。** 例: `test: current.res.status == 404` が成立すれば runbook は成功です。`expect: fail` は runbook 自体が失敗することを期待する検知テスト用です。`hookFail` は SQL フックの失敗を期待する場合です。

SQL フックの実行順は次のとおりです。

```text
before: 環境 hooks.before → スイート hooks.before → runbook runnora.before
        runbook の steps
after:  runbook runnora.after → スイート hooks.after → 環境 hooks.after
```

スイートのフックは `--suite` で実行したときだけ有効です。include 先の `runnora:` は使われません。SQL フックは runn の `db` ステップとは別機能で、`environments.<名前>.oracle` が接続先です。

## 4. `steps`：操作と検証

名前付きステップを上から順に書きます。`req` / `greq` / `db` / `include` / `exec` のような主操作の後に、同じステップの `bind` と `test` を書けます。`test` だけのステップも可能です。`desc` は説明、`if` は実行条件、`loop` は繰り返しです。

| 参照 | 内容 |
|---|---|
| `vars.x` | runbook の `vars.x` |
| `steps.call.res.body` | 名前 `call` の HTTP ステップの JSON 応答本文 |
| `current` | 今のステップの結果。同じステップ内の `test` で使う |
| `previous` | 直前のステップの結果 |
| `i` | `loop` の 0 始まりの反復番号 |
| `env.NAME` | runn が runbook 開始時に取得した環境変数 |
| `parent` | include 先から見た親 runbook の値 |
| `loan_id` | `bind` で保存した値 |

`${API_URL}` は **ファイル読込時の環境変数展開**、`{{ vars.id }}` は **ステップ実行時の値埋め込み**、`test: steps.call.res.status == 200` は **真偽値を返す式**です。式の中に `{{ }}` を重ねません。YAML 上で引用符が必要な式は、`'...'` または `|` を使います。

```yaml
vars:
  member_id: M0001
steps:
  fetch:
    req:
      /members/{{ vars.member_id }}:
        get:
          body: null
    test: current.res.status == 200
  save_count:
    bind:
      active_count: steps.fetch.res.body.activeLoanCount
  verify:
    test: active_count == 0
```

### HTTP（`req`）

```yaml
runners:
  req:
    endpoint: ${API_URL}
    openapi3: ../../openapi/library-api.yaml
    skipValidateRequest: true
steps:
  create:
    req:
      /loans:
        post:
          headers:
            X-Test-Scenario: LIB-001
          body:
            application/json:
              memberId: M0001
              bookId: B0001
    test: |
      current.res.status == 201 &&
      current.res.body.memberId == "M0001"
```

`req` は `runners.req` で定義した名前です。`/<path>` → 小文字の HTTP メソッド → `headers` / `body` の順に置きます。GET など本文のない要求では `body: null` を使います。`application/json` は本文の Content-Type です。応答では `res.status`、`res.headers`、`res.body`（解析済み JSON）、`res.rawBody`（生本文）を参照できます。`openapi3` はリクエスト・レスポンスを定義と照合し、`skipValidateRequest: true` は異常系の入力を送る場合などにリクエスト側の検証を省きます。

### DB（`db`）と `exec`

```yaml
runners:
  db: ${ORACLE_DSN}
steps:
  check_row:
    db:
      query: SELECT status FROM loans WHERE loan_id = 1
    test: len(current.rows) == 1 && current.rows[0].STATUS == "ACTIVE"
```

DB ステップの SELECT 結果は `current.rows`、更新系では `current.rows_affected` などに記録されます。DB ランナーは runn の機能です。runnora の `oracle` / `hooks` とは接続定義も用途も別です。`exec` は runn の外部コマンド実行で、`runn.scopes: [run:exec]` などの許可が必要です。実行結果は `current.stdout`、`current.stderr`、`current.exit_code` を参照します。

### gRPC（`greq`）

```yaml
runners:
  greq:
    addr: ${GRPC_ADDR}
    tls: false
    importPaths: [../proto]
    protos: [../proto/library.proto]
steps:
  get_book:
    greq:
      sample.library.v1.LibraryService/GetBook:
        message:
          book_id: B0001
    test: current.res.status == 0
```

RPC 名は `package.Service/Method`。Unary は `res.message`、server streaming は `res.messages`（配列）、gRPC の結果コードは `res.status` で参照します。送信に `message`（単一）または `messages`（client streaming）を使います。フィールド名と期待 JSON は、実際に runn が出す proto の名前に合わせます。サーバーリフレクションを使える場合は proto 指定なしの構成も可能です。

### 再利用（`include`）と繰り返し（`loop`）

```yaml
steps:
  case_B0001:
    include:
      path: ./get_getBook.template.yml
      vars:
        case: json://../../cases/contract/books/get_getBook/01_B0001.json
        expected: json://../../fixtures/responses/getBook/getBook_B0001.json
```

include 先は独立した runbook で、`include.vars` はその runbook の `vars` を上書きします。記録値は include ステップの下に入ります。各ケースの失敗を独立に報告したいときは、上のようにケースごとの include ステップを明示します。

上の `get_getBook.template.yml` は、渡された `case` と `expected` を次のように使います。`case` JSON は `pathParams.bookId`、`headers`、`expect.status`、`expect.ignorePaths` などを持つ、このリポジトリの**ケース形式**です。これらのフィールド名は runn 共通の予約語ではありません。

```yaml
vars:
  case: {}
  expected: {}
runners:
  req:
    endpoint: ${RUNNORA_BASE_URL}
steps:
  call_api:
    req:
      /books/{{ vars.case.pathParams.bookId }}:
        get:
          headers: "{{ vars.case.headers }}"
  check_call_api:
    test: |
      steps.call_api.res.status == vars.case.expect.status &&
      compare(steps.call_api.res.body, vars.expected, vars.case.expect.ignorePaths)
```

```yaml
steps:
  wait_for_result:
    loop:
      count: 5
      until: current.res.status == 200
      interval: 0.2
    req:
      /jobs/123:
        get:
          body: null
```

`loop.count` は最大回数、`until` が真になれば終了し、最後まで真にならなければ失敗です。再試行用の同じステップに `test` を置くと初回の失敗で止まり得るため、`until` を判定に使います。`i` は 0 始まりです。`loop` + `include` で独立したテストケースを回す場合は、途中の失敗の扱いを確認してください。このリポジトリの契約テストは各ケースを個別の include ステップにしています。

## 5. 比較式と外部データ

| 記法 | 用途 |
|---|---|
| `test: current.res.status == 200` | 一つの真偽式で判定する |
| `test: len(current.res.body.items) == 2` | 配列長を確認する |
| `test: compare(actual, expected)` | runn 標準の構造比較 |
| `compare(actual, expected, ignorePaths)` | 変動項目を jq 形式のパスで除外して比較する |
| `diffEps(expected, actual[, rules])` | runnora 固有。数値に許容誤差を付けて構造比較する |
| `loadJSON("cases/expected.json")` | runnora 固有。大きな整数を丸めずに JSON を読む |

```yaml
vars:
  expected: json://../cases/expected.json
steps:
  compare_exact:
    test: compare(steps.call.res.body, vars.expected)
  compare_numeric:
    test: 'diffEps(vars.expected, steps.call.res.body, "cases/tolerances.yaml")'
```

`diffEps()` は差分なしで `true`、差分ありで `false`。第 3 引数はプロジェクトルート基準の設定ファイル、または `{"default": {"abs": 1e-6}}` のような設定マップです。省略すれば許容誤差なしです。設定例:

```yaml
default:
  abs: 1e-6
  rel: 0
tolerances:
  - path: .series[].statistics.variance
    abs: 0.0001
```

gRPC の 64 ビット整数は ProtoJSON で文字列になることがあります。`diffEps()` は取得した RPC レスポンスの descriptor に基づき対象フィールドを数値として比較します。期待 JSON に大きな整数がある場合は、`json://` で丸められた値を使わず `diffEps(loadJSON("cases/expected.json"), current.res.message)` とします。`loadJSON()` のパスはプロジェクトルート基準です。

## 6. multipart の二つの書き方

単純なファイル送信は runn 標準の `multipart/form-data` と `file://` を使います。`file://` は **runbook の位置**から見たパスです。フォームの数値・真偽値は文字列にします。

```yaml
body:
  multipart/form-data:
    image: file://../../fixtures/uploads/cover.png
    caption: 表紙
    primary: "true"
```

各パートの Content-Type を指定する場合は、このリポジトリの multipart テストで使う `multipart()` を使います。**利用する runnora バイナリがこの関数に対応していることを確認してください**（multipart テストの要件は v0.5.0 以降）。`file` のパスは **プロジェクトルート**から見たパスです。戻り値の `contentType` には boundary が含まれ、`body` は送信用バイト列です。

```yaml
steps:
  prepare:
    bind:
      upload: 'multipart({"metadata": {"contentType": "application/json", "value": vars.metadata}, "file": {"contentType": "text/csv", "file": "fixtures/data.csv", "filename": "import.csv"}})'
  send:
    req:
      /upload:
        post:
          headers:
            Content-Type: "{{ upload.contentType }}"
          body:
            application/octet-stream: "{{ upload.body }}"
```

`multipart()` のパートには `value` または `file` を渡し、`contentType` と任意の `filename` を指定します。`application/json` の `value` がオブジェクトなら関数が JSON 化します。runn 標準の multipart と混ぜる必要はありません。

## 7. 相対パス早見表

| 書く場所・記法 | 基準 |
|---|---|
| `runnora.yaml` 内の `select.paths`、`hooks`、`report.dir` など | `runnora.yaml` のあるプロジェクトルート |
| runbook の `runnora.before / after` | プロジェクトルート |
| runn の `include.path`、`openapi3`、`protos`、`json://`、ステップの `file://` | その記法を持つ runbook の位置 |
| runnora の `diffEps()` 設定パス、`loadJSON()`、`multipart()` の `file` | プロジェクトルート |

特に `include.vars` の `json://...` は include 先の runbook が値を解決するため、template の配置も合わせて確認します。`vars` に `file://...` を置くとファイルの中身として読み込まれます。送信するファイルのパスを文字列のまま持ちたいときは、その違いに注意してください。

## 8. 検査・実行・結果の確認

テストセットのディレクトリ（`runnora.yaml` のある場所）から実行します。

```powershell
runnora validate --env unit
runnora list -l 'runbooks/**/*.yml'
runnora run runbooks/scenarios/lib-001-loan-lifecycle.yml
runnora run --suite scenarios
runnora run --suite scenarios --var API_URL=http://127.0.0.1:18081
```

`validate` は設定、変数、SQL パス、シナリオ ID などを実行前に検査します。API や DB の応答が正しいかは `run` で確かめます。実行ごとの `reports/<日時>-<スイート名>/`（直接実行は `<日時>-run`）には `summary.html`、`report.json`、`evidence/` が保存されます。HTTP・gRPC・DB・exec の応答証跡は自動保存されるため、通常は証跡用 `dump` ステップを書きません。`evidence.mode: full` でリクエストも保存できます。

よくある確認点:

| 症状 | 確認点 |
|---|---|
| `${NAME}` が未定義 | `runnora.yaml` の環境・スイート `vars`、OS 環境変数、`--var`。`runnora validate --env <環境>` を実行 |
| `{{ ... }}` の参照が失敗 | `vars` / `steps` / `current` の範囲、ステップ名、応答の JSON のキー名 |
| スイートに runbook が現れない | `select.paths`、`labels` / `ids`、トップレベルの `runnora.id` |
| ファイルが見つからない | 7 章のパス基準と include 先の配置 |
| API の 4xx を確認したら runbook が失敗 | HTTP ステータスの `test` と OpenAPI 応答検証を確認。`runnora.expect: fail` で隠さない |
| `diffEps()` で数値が一致しない | 期待値・実際値・許容誤差設定・64 ビット整数の読み込み方法を確認 |

## 9. 旧形式との違いと参照元

`config.yaml`、`--config`、`--before-sql`、`--after-sql` は旧形式です。現行形式では `runnora.yaml` と各 runbook の `runnora:` に移します。旧形式の移行には `runnora-migrate` を使います。

この文書は、次の実装・サンプルと照合して作成しました。特定機能の細部を調べる際は、対応する資料も参照してください。

- [runn v1.9.2 の公式 README](https://github.com/k1LoW/runn/tree/v1.9.2#readme)：runbook、ランナー、式、include、loop の仕様。
- [runnora の format v2 設計](https://github.com/ramsesyok/runnora/blob/main/docs/design/format-v2.md)：プロジェクト設定と `runnora:` の仕様。現行の細部は `internal/project`、`internal/scenario` の実装を優先。
- [runnora の README](https://github.com/ramsesyok/runnora#readme)：CLI、レポート、`diffEps()`、`loadJSON()`。
- このリポジトリの [コマンドマニュアル](command-manual.md)、[用語解説](test-basics.md)、[HTTP シナリオ](../api-test/runbooks/scenarios/lib-001-loan-lifecycle.yml)、[gRPC シナリオ](../grpc-test/runbooks/series-analysis.yml)、[multipart シナリオ](../multipart-test/runbooks/json-csv.yml)。
