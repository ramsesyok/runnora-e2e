# JSON + CSV の multipart トライアル

Spring Boot の `@RequestPart("metadata") Metadata` と `MultipartFile` を受ける実 API で、
従来方式の 415 と、runnora の `multipart()` 関数による成功を比較する。Oracle は使用しない。
既存の api-test / grpc-test とは独立したテストセット。

## 構成と実行

- Java 17、Spring Boot 2.7.15 / Spring Framework 5.3.29。手元の既存キャッシュで再現するため固定したトライアル環境。
- 通常のビルドには Maven、オフラインの `-UseCachedJars` には `~/.m2/repository` の指定バージョンの JAR が必要。
- `multipart()` を実装した runnora のブランチ `codex/multipart-part-content-type` からビルドした実行ファイルが必要。
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
