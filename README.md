# runnora-e2e

> [!IMPORTANT]
> **このリポジトリのサンプルは旧形式（runnora `v0.3.0` まで）で書かれています。**
> runnora の `main` は新形式（`runnora.yaml` と runbook の `runnora:` ブロック）に移行し、旧形式の `config.yaml`・`--config`・`--before-sql`・`--after-sql` を読まなくなりました（[新形式の詳細設計](https://github.com/ramsesyok/runnora/blob/main/docs/design/format-v2.md)）。
> 移行ツール `runnora-migrate` を作成中で、完成後にこのリポジトリを新形式に書き換えます。旧形式のサンプルはタグ `format-v1` に残します。
>
> それまでの間、サンプルは runnora `v0.3.0` で実行してください。
>
> ```powershell
> git -C ..\runnora checkout v0.3.0                      # 隣のフォルダの runnora を旧形式の最終版にする
> go -C ..\runnora build -o runnora.exe .                # api-test が使う runnora.exe を作り直す（grpc-test はスクリプトがビルドする）
> ```

**runnora** と周辺ツール（oapi2wire / runnora-docgen / runnora-diff）を使ったテストの、フルセット検証用サンプル集です。
対象のプロトコルごとにテストセットのフォルダを分けています。各フォルダは独立していて、それぞれのフォルダで実行します。
HTTP と gRPC の各応答は runbook の判定前に JSON ファイルへ保存し、テストレポートとともに各テストセットの `reports/` に残します。

| フォルダ | 対象 | 内容 | 状態 |
|---|---|---|---|
| [api-test/](api-test/README.md) | WebAPI（HTTP） | 図書貸出 API（Go + Oracle）、oapi2wire による WireMock モック、生成・契約・シナリオテスト、PL/SQL 前後処理、runnora-docgen による手順書 | 作成済み |
| [grpc-test/](grpc-test/README.md) | gRPC | Unary / Server streaming と、階層・配列を含む系列分析を許容誤差付きで比較する E2E runbook、runnora-docgen 手順書 | 作成済み |

ツール群の連携方針（今後このリポジトリを新形式の見本に書き直す予定）は [runnora の連携設計](https://github.com/ramsesyok/runnora/blob/main/docs/integration-design.md) を参照してください。

## 前提とするフォルダ配置

ツールは、このリポジトリと同じ階層にある各リポジトリのソースまたは実行ファイルを使います（各テストセットの README を参照）。

```text
Projects/
├─ runnora/            runnora.exe（テスト実行）
├─ oapi2wire/          oapi2wire.exe（WireMock モック生成）
├─ runnora-diff/       runnora-diff.exe のビルド元（数値の許容誤差比較）
├─ runnora-docgen/     runnora-docgen.exe（手順書の表生成）
└─ runnora-e2e/        このリポジトリ
   ├─ api-test/
   └─ grpc-test/
```
