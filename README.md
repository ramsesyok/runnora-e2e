# runnora-e2e

> [!NOTE]
> **このリポジトリのサンプルは新形式（`runnora.yaml` と runbook の `runnora:` ブロック）で書かれています**（[新形式の詳細設計](https://github.com/ramsesyok/runnora/blob/main/docs/design/format-v2.md)）。
> 旧形式（runnora `v0.3.0` まで。`config.yaml`・`--config`・`--before-sql`・`--after-sql`）のサンプルはタグ `format-v1` に残しています。
> 新形式へは [runnora-migrate](https://github.com/ramsesyok/runnora/blob/main/docs/migrate.md) で移行し、ツールが報告した TODO を手で直しました（移行の入力と結果は runnora の `internal/migrate/testdata/` にゴールデンデータとして置いています）。
>
> 隣のフォルダの runnora と runnora-docgen は `main` の最新版を使ってください。

**runnora** と周辺ツール（oapi2wire / runnora-docgen）を使ったテストの、フルセット検証用サンプル集です。
対象のプロトコルごとにテストセットのフォルダを分けています。各フォルダは独立していて、それぞれのフォルダで実行します。
HTTP と gRPC の各応答は runnora が証跡として自動で JSON ファイルに保存し、レポート（`summary.html`・`report.json`）とともに各テストセットの `reports/<日時>-<スイート名>/` に残します。

| フォルダ | 対象 | 内容 | 状態 |
|---|---|---|---|
| [api-test/](api-test/README.md) | WebAPI（HTTP） | 図書貸出 API（Go + Oracle）、oapi2wire による WireMock モック、生成・契約・シナリオテスト、PL/SQL 前後処理、runnora-docgen による手順書 | 作成済み |
| [grpc-test/](grpc-test/README.md) | gRPC | Unary / Server streaming と、階層・配列を含む系列分析を許容誤差付きで比較する E2E runbook、runnora-docgen 手順書 | 作成済み |

ツール群の連携方針は [runnora の連携設計](https://github.com/ramsesyok/runnora/blob/main/docs/integration-design.md) を参照してください。

| 資料 | 内容 |
|---|---|
| [はじめて読む人のためのテスト用語](docs/test-basics.md) | runbook・シナリオ・ケース・スイートの違い、スイートの要否、契約テストの意味を実例で説明 |
| [コマンドマニュアル](docs/command-manual.md) | スクリプトを使わず、runnora・oapi2wire・runnora-docgen のコマンドだけでテストの一連の流れ（モック生成 → テスト雛形 → モック / 実環境で実行 → 結果確認 → 手順書）を行う手順と早見表 |
| [スクリプトの処理解説](docs/scripts-explained.md) | `api-test/scripts/run-all.ps1` と `grpc-test/scripts/run.ps1` が内部で何を・どの順で・何のために実行しているか |

## runnora.yaml とスクリプトの分担

各テストセットでは、テストの中身を `runnora.yaml`（環境の接続先と共通の前後処理、runbook をまとめて流すスイート）と、
各 runbook の `runnora:` ブロック（シナリオ ID、固有の前後処理、期待する結果）に書きます。
スクリプト（`scripts/*.ps1`）に残るのは、runnora の範囲外である**テスト対象の環境の起動と停止**と、ツールを呼ぶ部分だけです。

| スクリプトに残るもの | 理由 |
|---|---|
| Oracle・API・WireMock・gRPC サーバの起動と停止、起動待ち | テスト対象の環境の用意は runnora の範囲外（連携設計 3 章） |
| oapi2wire によるモック資産の生成、ツールのビルド、手順書の発行（ddq） | 同上 |
| `runnora run --suite <名前>`、`runnora-docgen generate --suite <名前>` の呼び出し | どの環境・どの runbook・どの前後処理かはスイートが決めるので、スクリプトは名前を渡すだけ |

旧形式ではスクリプトが持っていた、runbook ごとの前後処理 SQL（`--before-sql` / `--after-sql`）、期待する終了コード、
接続先の環境変数（`RUNNORA_BASE_URL`）、`--config` の切り替えは、すべて `runnora.yaml` と `runnora:` ブロックに移りました。
レポートと証跡の保存先（`reports/<日時>-<スイート名>/`）は runnora が決めるので、スクリプトはフォルダを作らず、`RUNNORA_EVIDENCE_DIR` も設定しません。
runbook には応答を保存する `dump` ステップを書きません。数値の許容誤差付き比較は、runnora-diff を `exec` で呼ぶ代わりに runnora の `diffEps()` を使います。

## 前提とするフォルダ配置

ツールは、このリポジトリと同じ階層にある各リポジトリのソースまたは実行ファイルを使います（各テストセットの README を参照）。

```text
Projects/
├─ runnora/            runnora.exe（テスト実行）
├─ oapi2wire/          oapi2wire.exe（WireMock モック生成）
├─ runnora-docgen/     runnora-docgen.exe（手順書の表生成）
└─ runnora-e2e/        このリポジトリ
   ├─ api-test/
   └─ grpc-test/
```


## ライセンス

自作部分は [MIT License](LICENSE)（Copyright (c) 2026 ramsesyok）です。
文書テンプレートの元の表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、
サンプルの依存と外部テスト環境の条件は [ライセンス方針](docs/license-policy.md) を参照してください。
