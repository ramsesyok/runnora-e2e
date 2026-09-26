# runnora-e2e

**runnora** と周辺ツール（oapi2wire / runnora-docgen）を使ったテストの、フルセット検証用サンプル集です。
対象のプロトコルごとにテストセットのフォルダを分けています。各フォルダは独立していて、それぞれのフォルダで実行します。

| フォルダ | 対象 | 内容 | 状態 |
|---|---|---|---|
| [api-test/](api-test/README.md) | WebAPI（HTTP） | 図書貸出 API（Go + Oracle）、oapi2wire による WireMock モック、生成・契約・シナリオテスト、PL/SQL 前後処理、runnora-docgen による手順書 | 作成済み |
| grpc-test/ | gRPC | gRPC アプリのテストセット | 作成予定 |

## 前提とするフォルダ配置

ツールは、このリポジトリと同じ階層にある各リポジトリの実行ファイルを既定で使います（環境変数で変更できます。各テストセットの README を参照）。

```text
Projects/
├─ runnora/            runnora.exe（テスト実行）
├─ oapi2wire/          oapi2wire.exe（WireMock モック生成）
├─ runnora-docgen/     runnora-docgen.exe（手順書の表生成）
└─ runnora-e2e/        このリポジトリ
   ├─ api-test/
   └─ grpc-test/
```
