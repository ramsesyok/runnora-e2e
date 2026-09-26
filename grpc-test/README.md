# grpc-test：gRPC E2E テストセット

Go 製の図書照会・計算配信 gRPC サーバを、runnora の runbook から検証するサンプルです。`grpc-test/` を作業ディレクトリとして実行します。
API 契約は [proto/library.proto](proto/library.proto) に置き、サーバと runbook が同じ定義を使います。
サーバは Go で proto を起動時に読み込むため、`protoc` は不要です。Oracle と oapi2wire は使用しません。

| RPC | runbook | 確認すること |
|---|---|---|
| Unary `GetBook` | [runbooks/unary.yml](runbooks/unary.yml) | gRPC ステータス、蔵書 ID、タイトル、ジャンル、在庫数 |
| Server streaming `ListBooks` | [runbooks/server-streaming.yml](runbooks/server-streaming.yml) | JSON ファイルの検索条件と Unary 応答のジャンルを照合し、メッセージ配列の件数・順序・内容を確認 |
| Server streaming `Calculate` | [runbooks/calculation-streaming.yml](runbooks/calculation-streaming.yml) | 途中の計算結果を逐次配信し、最後だけ `optional completion` に集計結果を含める |
| Unary `AnalyzeSeries` | [runbooks/series-analysis.yml](runbooks/series-analysis.yml) | 複数系列のサンプル・統計・全体集計を、基準とパス別の許容誤差で比較 |

## 構成

```text
grpc-test/
├─ proto/library.proto         gRPC の定義（Unary / Server streaming）
├─ cmd/libraryd/main.go        Go 製の実サーバ（127.0.0.1:19090）
├─ cases/                     RPC 入力・期待値の JSON ファイル
├─ runbooks/                  runnora の E2E ケース
├─ config.yaml                DB フックなしの runnora 設定
├─ docs/                      runnora-docgen の表を組み込む Quarto 手順書
└─ scripts/                   テスト実行・手順書生成
```

## 必要なもの

- Go 1.24 以降（初回ビルド時は Go モジュールを取得できる環境）
- [runnora](https://github.com/ramsesyok/runnora) のソース（既定: `../../runnora/` からビルド、既存バイナリを使う場合は `RUNNORA_EXE`）
- [runnora-diff](https://github.com/ramsesyok/runnora-diff) のソース（既定: `../../runnora-diff/`、別の場所にある場合は `RUNNORA_DIFF_SOURCE_DIR` にソースディレクトリを指定）
- [runnora-docgen](https://github.com/ramsesyok/runnora-docgen)（既定: `../../runnora-docgen/runnora-docgen.exe`、変更時は `RUNNORA_DOCGEN_EXE`）
- 手順書を HTML 発行する場合は Quarto と ddq 2.4.0

## 実行

PowerShell で次を実行します。スクリプトがサーバ・runnora・jsondiff-eps をビルドし、サーバ起動後に 4 本の runbook と RPC カバレッジを確認して停止します。

```powershell
./scripts/run.ps1
./scripts/build-docs.ps1
./scripts/build-docs.ps1 -Pdf  # HTML と PDF の両方を発行
```

テスト結果は `reports/<日時>/`、HTML 手順書は `docs/_book/index.html`、PDF は [docs/design-doc.pdf](docs/design-doc.pdf) に出力します。
原稿だけを更新するときは `./scripts/build-docs.ps1 -GenerateOnly` を使えます。

runbook を直接実行する場合は、サーバを別ターミナルで起動します。

```powershell
go run ./cmd/libraryd -proto proto/library.proto
```

```powershell
./bin/runnora.exe run --config config.yaml --scopes run:exec `
  runbooks/unary.yml runbooks/server-streaming.yml runbooks/calculation-streaming.yml runbooks/series-analysis.yml
```

## runbook の読みどころ

1. [Unary](runbooks/unary.yml) は `vars.request` と `vars.expected` に `json://` で [入力](cases/unary/get-book-request.json)・[期待値](cases/unary/get-book-expected.json)を読み込みます。`message: "{{ vars.request }}"` で JSON オブジェクトを送信し、期待 JSON の `status` と `message` で gRPC ステータスと応答全体を比較します。
2. [Server streaming](runbooks/server-streaming.yml) も [検索入力](cases/server-streaming/list-books-request.json)と[期待するステータス・メッセージ配列](cases/server-streaming/list-books-expected.json)を JSON ファイルから読み込みます。`bind` で保存した Unary 応答のジャンルが検索入力と一致することを確かめ、`current.res.messages` を配列全体で比較します。配列の順序も検証対象です。
3. [計算ストリーミング](runbooks/calculation-streaming.yml) は [入力](cases/calculation-streaming/request.json)の `2, 3, 5` を順に加算して配信します。[期待 JSON](cases/calculation-streaming/expected.json)には `completion` を最後のメッセージだけに書き、途中では未設定であることも含めて比較します。
4. [系列分析](runbooks/series-analysis.yml) は階層・配列を持つ応答を [期待 JSON](cases/series-analysis/expected.json) と照合します。[許容誤差設定](cases/series-analysis/tolerances.yaml)は基準の絶対誤差、サンプルの絶対誤差、統計の相対誤差、分散の狭い絶対誤差、全体の加重平均の絶対誤差を指定します。許容誤差なしでは差分が出ることも確認します。`exec` ステップには `--scopes run:exec` が必要です。
5. runnora の gRPC 応答では、proto の `book_id` や `available_copies` をそのままの名前で参照します。
6. [手順書生成スクリプト](scripts/build-docs.ps1)は `--proto` を runnora-docgen に渡し、Unary と Server streaming の RPC 種別を表に載せます。

このサンプルは固定の蔵書データと計算結果を返す実サーバを使用します。モックへの照合ではなく、gRPC 通信とストリーム受信を通した E2E ケースです。
