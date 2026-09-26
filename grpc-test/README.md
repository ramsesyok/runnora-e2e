# grpc-test：gRPC E2E テストセット

Go 製の図書照会 gRPC サーバを、runnora の runbook から検証するサンプルです。`grpc-test/` を作業ディレクトリとして実行します。
API 契約は [proto/library.proto](proto/library.proto) に置き、サーバと runbook が同じ定義を使います。
サーバは Go で proto を起動時に読み込むため、`protoc` は不要です。Oracle と oapi2wire は使用しません。

| RPC | runbook | 確認すること |
|---|---|---|
| Unary `GetBook` | [runbooks/unary.yml](runbooks/unary.yml) | gRPC ステータス、蔵書 ID、タイトル、ジャンル、在庫数 |
| Server streaming `ListBooks` | [runbooks/server-streaming.yml](runbooks/server-streaming.yml) | Unary 応答から `bind` したジャンルで検索し、メッセージ配列の件数・順序・内容を確認 |

## 構成

```text
grpc-test/
├─ proto/library.proto         gRPC の定義（Unary / Server streaming）
├─ cmd/libraryd/main.go        Go 製の実サーバ（127.0.0.1:19090）
├─ runbooks/                  runnora の E2E ケース
├─ config.yaml                DB フックなしの runnora 設定
├─ docs/                      runnora-docgen の表を組み込む Quarto 手順書
└─ scripts/                   テスト実行・手順書生成
```

## 必要なもの

- Go 1.24 以降（初回ビルド時は Go モジュールを取得できる環境）
- [runnora](https://github.com/ramsesyok/runnora)（既定: `../../runnora/runnora.exe`、変更時は `RUNNORA_EXE`）
- [runnora-docgen](https://github.com/ramsesyok/runnora-docgen)（既定: `../../runnora-docgen/runnora-docgen.exe`、変更時は `RUNNORA_DOCGEN_EXE`）
- 手順書を HTML 発行する場合は Quarto と ddq 2.4.0

## 実行

PowerShell で次を実行します。スクリプトがサーバをビルド・起動し、両方の runbook と RPC カバレッジを確認して停止します。

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
../../runnora/runnora.exe run --config config.yaml runbooks/unary.yml runbooks/server-streaming.yml
```

## runbook の読みどころ

1. [Unary](runbooks/unary.yml) の `greq` はリクエストを `message` で渡し、`current.res.message` と gRPC ステータス `0` を検証します。
2. [Server streaming](runbooks/server-streaming.yml) は先に Unary の応答を取得し、`bind` でジャンルを後続のリクエストへ渡します。受信した各応答は `current.res.messages` の配列に入ります。
3. runnora の gRPC 応答では、proto の `book_id` や `available_copies` をそのままの名前で参照します。
4. [手順書生成スクリプト](scripts/build-docs.ps1)は `--proto` を runnora-docgen に渡し、Unary と Server streaming の RPC 種別を表に載せます。

このサンプルは固定の蔵書データを返す実サーバを使用します。モックへの照合ではなく、gRPC 通信とストリーム受信を通した E2E ケースです。
