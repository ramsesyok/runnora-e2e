# はじめて読む人のためのテスト用語

このページは、runnora-e2e のファイルを読む前に「何を1件のテストと呼び、何をまとめて実行するのか」をつかむための案内です。コマンドの詳しい手順は [コマンドマニュアル](command-manual.md) を参照してください。

## まずは4つの言葉

| 言葉 | このリポジトリでの意味 | 実例 |
|---|---|---|
| **runbook** | 実行する手順を書いた YAML ファイル。API の呼び出しや結果の確認を `steps` に順番に書く | [LIB-001](../api-test/runbooks/scenarios/lib-001-loan-lifecycle.yml) |
| **シナリオ** | 「利用者が何をして、どの状態になるか」という一連の流れ。通常は1本の runbook で表す | `LIB-001`：本を借り、確認し、返す |
| **ケース** | 試すための具体的な条件・入力・期待結果 | [getBook の B0001 ケース](../api-test/cases/contract/books/get_getBook/01_B0001.json)：登録済みの本を取得する |
| **スイート** | 複数の runbook を、決めた環境や共通の前後処理でまとめて実行する設定 | [api-test/runnora.yaml](../api-test/runnora.yaml) の `scenarios` |

シナリオは「操作の流れ」、ケースは「そのテストで使う具体的な条件と値」です。1つのシナリオに複数の API 呼び出しや確認を含められます。ケースの値は JSON に分けても、runbook に直接書いても構いません。

## スイートは必ず必要ですか？

いいえ。対象の API と DB を起動した後、1本の runbook を直接実行できます。次のコマンドは `api-test/` で実行します。

```powershell
& ..\..\runnora\runnora.exe run runbooks/scenarios/lib-001-loan-lifecycle.yml
```

複数のシナリオを同じ条件で実行するときは、`runnora.yaml` のスイートを使います。

```powershell
& ..\..\runnora\runnora.exe run --suite scenarios
```

`scenarios` は `runbooks/scenarios/*.yml` と検知確認用の runbook を選び、`unit` 環境で実行します。スイートにだけ指定した前処理は、runbook を直接実行すると適用されません。たとえば `contract-unit` の `contract_setup.sql` が必要な契約テストは、スイートから実行してください。

> **名前の注意:** `runnora.yaml` の「スイート」は実行対象と環境をまとめる設定です。一方、`runbooks/contract/*.suite.yml` は複数のケースを呼ぶ **runbook のファイル名**です。どちらも「まとめる」役割ですが、同じファイルではありません。

## ケース JSON は必ず必要ですか？

いいえ。ケース JSON は、同じ API 呼び出しを異なる値で試すときに便利です。[getBook の契約テスト](../api-test/runbooks/contract/get_getBook.suite.yml)では、`B0001` と `not_found` のケースを同じ template runbook に渡します。一方、[LIB-001](../api-test/runbooks/scenarios/lib-001-loan-lifecycle.yml) は、貸出から返却までの入力と確認を runbook の各ステップに書いています。

[LIB-008](../api-test/runbooks/scenarios/lib-008-cover-upload.yml) も1本のシナリオです。PNG をアップロードした場合、画像ではないファイルを送った場合などを順に確認し、送信する実ファイルは `fixtures/uploads/` に置いています。このファイルは「ケース JSON」ではなく、テストに使うデータです。

## 契約テストとは何ですか？

API の「契約」は、呼び出し方と返答について提供側と利用側が共有する約束です。このサンプルでは [OpenAPI](../api-test/openapi/library-api.yaml) が API 定義の正本です。契約テストは具体的なケースで API を呼び、主に HTTP ステータス、応答本文、OpenAPI の応答スキーマとの整合性を確認します。

同じ契約テストを WireMock と実 API の両方に実行できます。モックでの成功は、想定したモックケースが選ばれることなどを確認します。応答本文の期待ファイルはモックの戻り値と共有しているため、**モックに対するテストだけで本文が業務的に正しいとは判断できません**。実 API への実行と、期待値そのもののレビューが必要です。

契約テストは1回の API 呼び出しを中心に確認します。「借りた後に在庫が減り、返すと元に戻る」といった操作をまたぐ結果は、ユーザシナリオの runbook で確認します。

## 生成テスト、契約テスト、シナリオテストの違いは？

| 種類 | 主な目的 | このサンプルの置き場所 |
|---|---|---|
| 生成テスト | OpenAPI から作った代表的な入力で、API 呼び出しの出発点を用意する | `api-test/runbooks/generated/`、`api-test/cases/generated/` |
| 契約テスト | 人が選んだ具体的なケースで、API の応答が定義と期待値に合うか確認する | `api-test/runbooks/contract/`、`api-test/cases/contract/` |
| シナリオテスト | 複数の操作や状態変化を通して、利用者の目的を達成できるか確認する | `api-test/runbooks/scenarios/` |

生成テストは業務上必要なケースをすべて作るものではありません。`LIB-008` の multipart/form-data も、アップロードの条件を手書きのシナリオで確認します。
`grpc-test/runbooks/` は gRPC の各 RPC を確認するテストで、必ずしも利用者の操作全体を表すシナリオではありません。

## 最初はどれから書きますか？

利用者の操作を確認したいなら、まず「誰が何を行い、最後にどうなれば成功か」を一文にします。次に必要な API 呼び出し、前提データ、各時点の期待結果を並べて、1本の runbook にします。単独で実行して確かめ、まとめて実行する段階でスイートに追加できます。

実際の実行方法は [api-test の README](../api-test/README.md) と [grpc-test の README](../grpc-test/README.md) を参照してください。
