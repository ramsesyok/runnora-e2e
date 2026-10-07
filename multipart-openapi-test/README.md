# OpenAPI 生成 Spring の multipart トライアル

[OpenAPI 定義](openapi.yaml) から Spring の API インターフェースと DTO を生成し、
複雑な JSON 2 パートと CSV を実サーバに送信する。
既存の [手書き Spring API のテスト](../multipart-test/README.md) とは独立したテストセット。

## 構成

- Java **17** / Spring Boot **2.7.15** / OpenAPI Generator **7.26.0**。
- runnora **v0.5.0** の公開 Windows 実行ファイルで動作確認。
- Maven と `curl.exe` が必要。初回ビルドは Maven Central から依存を取得する。
- 待ち受けは `127.0.0.1:18083`。Oracle や Docker は不要。

[pom.xml](server/pom.xml) の Generator プラグインで `mvn clean package` のたびに生成する。
生成先は Git 管理外の `server/target/generated-sources/openapi/`。
`generatorName: spring`、`interfaceOnly: true`、`useSpringBoot3: false` を指定する。
`javax.*` を使う Spring Boot 2 向けのコードを生成し、Bean Validation と Swagger 注釈は無効にしている。
このテストの対象は multipart の読み取りと DTO 変換であり、フィールドの入力制約の検証ではない。

生成した `MultipartUploadApi` は次の形になる。

```java
@RequestMapping(
    method = RequestMethod.POST,
    value = "/generated/upload",
    produces = { "application/json" },
    consumes = { "multipart/form-data" }
)
ResponseEntity<UploadSummary> uploadMultipart(
    @RequestPart(value = "metadata1", required = true) Metadata1 metadata1,
    @RequestPart(value = "metadata2", required = true) Metadata2 metadata2,
    @RequestPart(value = "csv", required = true) MultipartFile csv
);
```

[Controller](server/src/main/java/trial/GeneratedMultipartApplication.java) はこのインターフェースを実装し、
アップロード処理に独自の `@RequestMapping` / `@RequestPart` を付けない。
生成コードは編集しない。受信した DTO、パートの Content-Type、ファイル名、
CSV のサイズ・SHA-256・データ行数を応答として返す。

## 実行

リポジトリルートから、確認したい runnora 実行ファイルを指定する。

```powershell
./multipart-openapi-test/scripts/run.ps1 -RunnoraExe C:/tools/runnora.exe
```

スクリプトは生成・ビルド・起動・curl 比較・runbook 実行・証跡の照合・停止まで行う。
使用済みのポートは再利用しない。停止するのは自分で起動したサーバだけ。

## runbook の書き方

[正常系 runbook](runbooks/generated-success.yml) では次のように送信する。
`json://` のパスは runbook の場所を基準にし、`multipart()` のファイルパスは
`runnora.yaml` のある `multipart-openapi-test/` を基準にする。

```yaml
vars:
  metadata1: json://../fixtures/metadata1.json
  metadata2: json://../fixtures/metadata2.json
steps:
  prepare:
    bind:
      upload: 'multipart({"metadata1": {"contentType": "application/json", "value": vars.metadata1}, "metadata2": {"contentType": "application/json", "value": vars.metadata2}, "csv": {"contentType": "text/csv", "file": "fixtures/data.csv", "filename": "取込.csv"}})'
  send:
    req:
      /generated/upload:
        post:
          headers:
            Accept: "application/json"
            Content-Type: "{{ upload.contentType }}"
          body:
            application/octet-stream: "{{ upload.body }}"
    test: current.res.status == 200
```

外側の `metadata1` / `metadata2` / `csv` は OpenAPI のパート名に合わせる。
内側の `contentType` / `value` / `file` / `filename` は runnora の固定キー。
`value` と `file` はどちらか一方を指定する。
応答が JSON なので `Accept: "application/json"` を使う。
本文の `application/octet-stream` は runn の生バイト送信用キーで、
実際の HTTP Content-Type は boundary を含む `upload.contentType` になる。

### ヘッダー値はダブルクォーテーションで囲む

**`headers` の固定値はすべてダブルクォーテーションで囲む。**
数字の `"1"`、英字の `"R"` も同じ書き方に揃える。

```yaml
headers:
  Accept: "application/json"
  X-Request-ID: "1"
  X-Exerceis-ID: "R"
  Content-Type: "{{ upload.contentType }}"
```

カスタムヘッダー名と値は API の仕様に合わせる。
`X-Request-ID: 1` は YAML で数値になり、runn のヘッダー解析で `invalid request` になる。
`R` は引用符なしでも文字列になるが、表記を統一して `"R"` と書く。
引用符は YAML 用で、HTTP の値には付かない。変数を使う場合も、展開後の値が文字列であることを確認する。

### JSON 化は multipart() に任せる

**JSON オブジェクトを送る場合は、元の値を `value` に渡す。**
上の `"value": vars.metadata1` が正しい指定。
`"value": toJSON(vars.metadata1)` とすると、JSON テキストをさらに JSON 文字列としてシリアライズし、
この API の DTO 変換では **400** になる。

例えば `vars.metadata` が `{name: 取込データ}` の場合（本文の空白・改行を省略）：

| `value` に渡す式（contentType は application/json） | パート本文 | 受信する JSON の型 |
|---|---|---|
| `vars.metadata` | `{"name":"取込データ"}` | オブジェクト |
| `toJSON(vars.metadata)` | `"{\"name\":\"取込データ\"}"` | 文字列 |

API が JSON 文字列を要求する場合は `value` に文字列を渡せる。
このテストの API は JSON オブジェクトを要求するため、事前に文字列化する指定を避ける。
既存の JSON ファイルは `file` で中身をそのまま送る。
生成済みの `upload.body` も `toJSON()` を挟まず、上の送信例どおり直接参照する。

### 通常 multipart のテンプレート展開にも注意する

このテスト環境では、次の通常 multipart の指定も再現ケースとして残している。

```yaml
body:
  multipart/form-data:
    metadata1: "{{ toJSON(vars.metadata1) }}"
```

展開後の値がマップになり、送信前に `http request failed ... invalid body: map[...]` となる。
こちらは HTTP 応答がないクライアント側の失敗。
`multipart()` の二重シリアライズによる **HTTP 400** や、JSON パートの型が不正な場合の
**HTTP 415** と、失敗する段階を区別する。
`http request failed` だけでは原因を断定できないため、後続の詳細も確認する。
正常な送信には、このページの `multipart()` と生本文送信を組み合わせた例を使う。

## 検証内容

3 runbook・14 ステップを実行する。runnora の HTTP 応答は 7 件、curl の正常系は 1 件。
これに加えて、HTTP 送信前に失敗する 1 ケースを期待失敗として検証する。

| ケース | 期待する結果 |
|---|---|
| curl：JSON 2 ファイル + CSV（text/csv） | 200 |
| multipart()：複雑な JSON 2 オブジェクト + CSV、日本語ファイル名 | 200 |
| multipart()：JSON 2 ファイル + CSV | 200 |
| 通常の multipart/form-data：型指定のない JSON リテラル | 415 |
| metadata1 の Content-Type が text/plain | 415 |
| metadata2 の Content-Type が text/plain | 415 |
| metadata1 が JSON オブジェクトではなく JSON 文字列 | 400 |
| 必須の csv を file というパート名で送信 | 400 |
| 通常の multipart/form-data に `"{{ toJSON(vars.metadata1) }}"` を指定 | 送信前の `http request failed ... invalid body: map[...]` |

最後のケースでは runn の展開後の値がマップになり、通常の multipart エンコーダーが拒否する。
`expect: fail` に加えてエラー内容と HTTP 証跡がないことを照合する。
サーバでも受信数 **8**、Controller 呼び出し数 **3** を確認し、送信前の失敗と
Spring が Controller 呼び出し前に返す 415 / 400 を区別する。

正常系では OpenAPI のリクエスト・レスポンス検証を有効にする。
異常系ではサーバに不正なパートを届けるため、リクエスト検証だけを無効にする。
curl と runnora の正常系の応答を元の fixture と照合し、次を検査する。

- ネストした DTO、配列、数値、真偽値、null、空配列、日本語、引用符、改行の保持。
- CSV の元ファイルと受信したサイズ・SHA-256・2 行の一致。
- JSON 2 パートの application/json、CSV の text/csv、日本語ファイル名の保持。
- 実際の HTTP Content-Type と本文の boundary の一致、7 件の HTTP 証跡と HTML レポート。

OpenAPI の `encoding.csv.contentType: text/csv` を指定しているが、生成された
`MultipartFile` 引数に CSV の Content-Type を拒否する検査が自動で追加されるわけではない。
この Controller は受信した型を返して照合する。CSV の形式解析も対象外。
JSON パートの 415 は Spring の HttpMessageConverter による拒否で、独自に返したものではない。

この構成では `multipart()` による送信は生成 Spring API でも成功する。
利用中の Generator の別バージョン・設定や個別の OpenAPI 定義については、この結果だけでは保証しない。

## 証跡と CI

- `reports/<日時>-generated-multipart/`：report.json、summary.html、HTTP 証跡。
- `reports/curl-response.json`：curl の受信結果。
- `reports/toolchain.json`：実際に使用した Java / Spring Boot / Generator / runnora。
- `reports/final-health.json`：サーバの受信数と Controller 呼び出し数。
- `logs/maven.log` / `logs/spring.out.log` / `logs/spring.err.log`：生成・起動・変換エラーのログ。

[Multipart CI](../.github/workflows/multipart.yml) は、このフォルダの変更でも起動する。
[共通ワークフロー](../.github/workflows/multipart-reusable.yml) で既存の multipart テストと続けて実行し、
レポート・ログ・生成 Java コードを `multipart-spring-evidence` artifact に保存する。
自動実行では runnora v0.5.0 のコミットを固定し、手動実行では別の ref を指定できる。
runnora 本体側からの呼び出しに新テストを反映するには、本体 CI の E2E 参照 SHA も更新する必要がある。

## 実行結果（2026-10-06）

公開版 runnora v0.5.0、Java 17、Spring Boot 2.7.15、Generator 7.26.0 で、
上記 3 runbook・14 ステップが期待どおりの結果になった（送信前の期待失敗を 1 件含む）。
JSON 全フィールドと CSV のサイズ・SHA-256・パートの型が curl / runnora / 元 fixture で一致した。
受信数 8 / Controller 呼び出し数 3 も確認した。

- 新規テスト：`reports/20261006-221459-generated-multipart/`。
- 既存の手書き Spring E2E：`../multipart-test/reports/20261006-221327-multipart/`。2 runbook・14 ステップ成功。
- 証跡の JSON 配列値・CSV ハッシュ・送信前エラーの証跡有無を故意に壊した場合、照合スクリプトが拒否することも確認。
- PowerShell の構文検査、actionlint、Git の差分検査は成功。CI の結果は GitHub Actions と `multipart-spring-evidence` artifact で確認できる。
