# JSON + CSV の multipart トライアル

Spring Boot の `@RequestPart("metadata") Metadata` と `MultipartFile` を受ける実 API で、
従来方式の 415 と、runnora の `multipart()` 関数による成功を比較する。Oracle は使用しない。
既存の api-test / grpc-test とは独立したテストセット。

## 構成と実行

- Java 17、Spring Boot 2.7.15 / Spring Framework 5.3.29。手元の既存キャッシュで再現するため固定したトライアル環境。
- 通常のビルドには Maven、オフラインの `-UseCachedJars` には `~/.m2/repository` の指定バージョンの JAR が必要。
- `multipart()` を実装した runnora v0.5.0 以降の実行ファイルが必要。
- curl.exe を比較に使用する。待ち受けは `127.0.0.1:18082`。CSV・画像は保存せず、受信内容の要約を返す。

リポジトリルートから実行する。

```powershell
./multipart-test/scripts/run.ps1 -RunnoraExe /path/to/runnora.exe

# Maven を使わず、固定した既存キャッシュからコンパイルする場合
./multipart-test/scripts/run.ps1 -UseCachedJars -RunnoraExe /path/to/runnora.exe
```

この作業環境では、実装ブランチのチェックアウトを
`api-test/reports/multipart-trial/runnora-src/` に作成し、
実行ファイルを `api-test/bin/runnora-multipart.exe` に置いている。
`run.ps1 -UseCachedJars` はそのファイルを既定で使う。
これらは Git 管理外なので、新規 clone では自分で実装ブランチをビルドする。
このチェックアウトで再ビルドする場合は、`go.work` の相対参照を避けて実行する。

```powershell
$env:GOWORK = 'off'
go build -C api-test/reports/multipart-trial/runnora-src -o C:/Users/ramse/Projects/runnora-e2e/api-test/bin/runnora-multipart.exe .
```

スクリプトは Spring サーバをビルド・起動し、curl と runnora を実行してからサーバを停止する。
失敗した場合もログとレポートを残す。

## runbook の書き方

```yaml
vars:
  metadata:
    name: 日本語の取込
    kind: csv
    enabled: true
steps:
  prepare:
    bind:
      upload: 'multipart({"metadata": {"contentType": "application/json", "value": vars.metadata}, "file": {"contentType": "text/csv", "file": "fixtures/data.csv"}})'
  send:
    req:
      /upload:
        post:
          headers:
            Accept: application/json
            Content-Type: "{{ upload.contentType }}"
          body:
            application/octet-stream: "{{ upload.body }}"
```

`application/octet-stream` は runn の生本文送信を使うためのキー。
実際にはヘッダーの `upload.contentType` によって multipart として送信される。
ファイルパスは `runnora.yaml` のある `multipart-test/` 基準。
パートごとの指定を通常の `body: multipart/form-data:` に直接書く方式ではない。

JSON と CSV を混ぜても、応答が JSON の API なら `Accept: application/json` を使う。
全体の `Content-Type` は boundary を含む `upload.contentType` を使い、各パートの型は関数に渡す。

| パートの設定 | 内容 |
|---|---|
| `value` | 値。`contentType: application/json` なら JSON にシリアライズする。オブジェクトには YAML のマップを渡す |
| `file` | ファイルの中身をそのまま送る。`value` とどちらか一方だけ指定する |
| `contentType` | JSON は `application/json`、CSV は `text/csv`、PNG は `image/png` など、API が要求する型 |
| `filename` | ファイルの送信名。省略時はファイル名を使う |

JSON ファイルと名前を変えた CSV を送る場合：

```yaml
prepare:
  bind:
    upload: 'multipart({"metadata": {"contentType": "application/json", "file": "fixtures/metadata.json"}, "file": {"contentType": "text/csv", "file": "fixtures/data.csv", "filename": "import.csv"}})'
```

送信ステップは上の例と同じ。PNG の場合はファイルパートを
`{"contentType": "image/png", "file": "fixtures/cover.png"}` に置き換える。
JSON オブジェクトを送る場合は、`value` に `vars.metadata` のような元の値を渡し、JSON 化は `multipart()` に任せる。
`value` に `toJSON(vars.metadata)` を渡すと二重シリアライズになり、今回の Spring DTO では HTTP 400 になる。
API が JSON 文字列を要求する場合は `value` に文字列を渡せる。既存の JSON 本文は `file` を使う。
通常の `body: multipart/form-data:` の `"{{ toJSON(...) }}"` は、送信前に
`http request failed ... invalid body: map[...]` になる場合もある。
正しい例と失敗する段階の違いは [OpenAPI multipart テストの説明](../multipart-openapi-test/README.md#json-化は-multipart-に任せる) を参照。
`run` で利用でき、`loadt` への登録は対象外。
ファイル全体をメモリに読み込むため、大容量ファイルのストリーミング送信には対応していない。
本文全体の上限は **4 MiB（4,194,304 bytes）**。ファイル・JSON・ヘッダー・boundary の合計に適用する。
超過時は bind ステップでエラーになり、HTTP 送信は行わない。上限の解除設定はない。
ファイル名は日本語も使用でき、UTF-8 の `filename="取込.csv"` で送る（`filename*` は使わない）。

## CI

[Multipart ワークフロー](../.github/workflows/multipart.yml) は、このテストセットや PNG fixture の
push / pull request で実行する。手動実行では `runnora-ref` に検証したい runnora のコミット・ブランチを指定できる。
自動実行では v0.5.0 のコミット `d0a4f256b4ed5f2748cdfa753915af240bc49be8` を固定してビルドする。
同じジョブで [OpenAPI Generator から生成した Spring API のテスト](../multipart-openapi-test/README.md) も実行する。

[共通ワークフロー](../.github/workflows/multipart-reusable.yml) を runnora 側の CI からも呼び出し、
その push / pull request のコミットをビルドして同じテストを実行する。
E2E のワークフローと fixture は同一の固定コミットを使うため、E2E の main の変更だけで検証内容は変わらない。
テスト内容を更新する際は、runnora 側 CI の呼び出し SHA と `e2e-ref` も更新する。

Windows runner で Go・Java 17 を用意し、通常の Maven ビルドを使う。`-UseCachedJars` は指定しない。
builder の単体テスト、include / loop を通る runn の結合テスト、実 Spring Boot API の順に検証する。
全14ステップ・HTTP 7 件の結果、curl と CSV の SHA-256 / サイズ一致、PNG の保持、
HTTP ヘッダーとテキスト本文の boundary 一致、各証跡と HTML サマリーの保存を検査する。
PNG を含むリクエスト本文は既存の証跡機能でサイズの要約になるため、受信した PNG のハッシュで内容を確認する。
`MULTIPART-002` は日本語ファイル名と OpenAPI リクエスト検証を確認する。
本文サイズの境界、複数パートの合計、超過時の未送信は Go テストで確認する。
失敗時も `multipart-spring-evidence` artifact にレポート・curl 応答・Spring ログを14日間保存する。

両リポジトリの追加コミットをリモートに push すると参照可能になる。
初回は E2E 側の共通ワークフローを公開してから runnora 側の CI を実行する。
GitHub の Actions 設定で、リポジトリ間の再利用ワークフローが許可されている必要がある。

## 実行結果（2026-10-05）

Spring Boot の実 API に対して全12ステップが成功した。

| HTTP ステップ | 結果 | 確認内容 |
|---|---|---|
| legacy | 415 | 型指定なしの JSON 文字列で Spring の DTO 変換失敗を再現 |
| typed | 200 | JSON の DTO 化、日本語・真偽値、text/csv、CSV 2 行 |
| json_file | 200 | JSON ファイル、CSV ファイル名の指定、同じサイズ・SHA-256 |
| bad_json_type | 415 | JSON パートの text/plain を拒否 |
| bad_csv_type | 415 | サーバで CSV パートの application/octet-stream を拒否 |
| image | 200 | JSON + PNG、93 bytes、期待する SHA-256、false の値 |

curl と runnora の CSV 受信サイズ・SHA-256、およびローカルファイルの SHA-256 が一致した。
OpenAPI **応答**検証も成功。異常なパート型を送るためリクエスト検証は無効にしている。
サーバは CSV ファイルパートに text/csv を要求するチェックを持つが、CSV の一般的な解析器ではない。
415 の JSON パート側は Spring の HttpMessageConverter が返し、CSV パート側は Controller の明示チェックが返す。

ローカル証跡：

- `reports/20261005-181947-multipart/`：report.json、summary.html、HTTP 6 件のリクエスト・レスポンス
- `reports/curl-response.json`：成功した curl の応答
- `logs/spring.out.log`：Spring が application/octet-stream / text/plain を拒否したログ

CI 追加時には通常の Maven `package` でビルドした JAR でも全12ステップが成功した
（`reports/20261005-220952-multipart/`）。CI に組み込む Go テストと actionlint の構文検査も成功。
HTTP ステータス、CSV の SHA-256、boundary を壊した証跡を検証処理が拒否することを確認した。
マージ前の修正後は、通常 Maven ビルドで全14ステップ（2シナリオ・HTTP 7件）が成功した
（`reports/20261005-222808-multipart/`）。日本語ファイル名 `取込.csv` の送受信、
`filename*` / `name*` を使わないヘッダー、OpenAPI リクエスト検証の成功も確認した。
GitHub Actions の実行結果は Actions 画面と `multipart-spring-evidence` artifact で確認する。

既存の Oracle + Go API のシナリオも新しい runnora で再実行し、9/9 成功した
（`../api-test/reports/20261005-182045-scenarios/`、LIB-008 を含む）。

runnora の追加テストは任意のバイナリ、型指定、入力エラー、変数・include・loop、証跡保存を検証して成功。
`go vet ./internal/multipartbody ./internal/app` も成功。
`go test ./...` は Windows のパス表記に依存する既存の TestValidate と TestGolden_E2E、
および bash が WSL の bash.exe を参照する環境で TestCapturer_KeysAndFiles が失敗する。
変更前 `64bf851` でも同じテストが失敗することを確認した。今回 runn のコード・依存バージョンは変更していない。

## 依存ライブラリ

サンプルコードはこのリポジトリの MIT License に従う。Spring / Jackson / Tomcat などの JAR は
Maven または利用者の既存キャッシュから取得し、Git には同梱しない。
第三者ライブラリの許諾・表示は各配布物に従う。依存を含む JAR を再配布する場合は、
依存ライブラリの LICENSE / NOTICE も保持する。
