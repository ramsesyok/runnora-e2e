# runnora-e2e

**runnora** と周辺ツール（oapi2wire / runnora-docgen / runnora-diff）を使ったテストの、フルセット検証用サンプル集です。
対象のプロトコルごとにテストセットのフォルダを分けています。各フォルダは独立していて、それぞれのフォルダで実行します。

| フォルダ | 対象 | 内容 | 状態 |
|---|---|---|---|
| [api-test/](api-test/README.md) | WebAPI（HTTP） | 図書貸出 API（Go + Oracle）、oapi2wire による WireMock モック、生成・契約・シナリオテスト、PL/SQL 前後処理、runnora-docgen による手順書 | 作成済み |
| [grpc-test/](grpc-test/README.md) | gRPC | Unary / Server streaming と、階層・配列を含む系列分析を許容誤差付きで比較する E2E runbook、runnora-docgen 手順書 | 作成済み |

## 前提とするフォルダ配置

ツールは、このリポジトリと同じ階層にある各リポジトリのソースまたは実行ファイルを使います（各テストセットの README を参照）。

```text
Projects/
├─ runnora/            runnora.exe（テスト実行）
├─ oapi2wire/          oapi2wire.exe（WireMock モック生成）
├─ runnora-diff/       jsondiff-eps.exe のビルド元
├─ runnora-docgen/     runnora-docgen.exe（手順書の表生成）
└─ runnora-e2e/        このリポジトリ
   ├─ api-test/
   └─ grpc-test/
```
