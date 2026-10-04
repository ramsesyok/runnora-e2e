# ライセンスとテスト環境

このリポジトリの自作コード、runbook、サンプルデータ、文書は [MIT License](../LICENSE)、著作権名義は `Copyright (c) 2026 ramsesyok` です。商用利用、改変、再配布が可能です。コピーや重要部分を配布する際は、著作権表示と許諾表示を保持してください。第三者由来の素材・テンプレート・生成コードには元の条件が残ります。

## サンプルの Go 依存

固定バージョンの本文・著作権・ソース取得先は、次の表示ファイルに収録します。

- [API サーバ](../api-test/api/THIRD_PARTY_NOTICES.md)
- [OpenAPI 文書生成ツール](../api-test/tools/THIRD_PARTY_NOTICES.md)
- [gRPC サンプル](../grpc-test/THIRD_PARTY_NOTICES.md)

各サンプルのバイナリを別途配布する場合は、ルートの LICENSE と対応する表示を同梱してください。

```sh
go run scripts/licenses.go -module-dir api-test/api -output api-test/api/THIRD_PARTY_NOTICES.md
go run scripts/licenses.go -module-dir api-test/tools -output api-test/tools/THIRD_PARTY_NOTICES.md
go run scripts/licenses.go -module-dir grpc-test -output grpc-test/THIRD_PARTY_NOTICES.md
```

末尾に `-check` を付けると生成物の鮮度を検査します。Linux / macOS / Windows、amd64 / arm64、CGO 無効の通常ビルドが対象です。ソースの由来、ソースコメント内だけの許諾や、生成コードの追加条件は別途確認してください。

## 外部で取得・実行する製品

| 製品 | 扱い |
|---|---|
| runnora / oapi2wire / runnora-docgen / runnora-diff | 各ツールの LICENSE と THIRD_PARTY_NOTICES に従う。実行ファイルをコピーして配布する場合も表示を同梱する |
| Oracle Database Free | OSS ではなく Oracle Free Use Terms and Conditions の外部製品。未改変での開発・テスト・社内業務利用等と、条件付きの再配布が認められる。MIT として再許諾しない |
| WireMock / Java | 別途取得して実行する。WireMock のライセンスと依存表示、選択した Java 配布物の条件に従う |
| Docker Desktop | 実行環境の利用条件は契約・組織条件による。サンプルの MIT は Desktop の利用許諾を含まない |
| Quarto / Pandoc / Typst / ddq / PlantUML | 文書生成用の外部ツール。それぞれのライセンス・同梱物・出力素材の条件を確認する |

Oracle の未改変プログラムを再配布する場合には、Oracle の本文同梱、権利表示の保持、利用者へのプログラム利用の追加料金を課さない条件等があります。詳細は [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html) を参照してください。`api-test/docker-compose.yml` は外部の `container-registry.oracle.com/database/free:latest` を参照します。`latest` は内容が変わるため、実際に取得したイメージの契約・NOTICE を確認してください。

Oracle を利用するこのテスト環境に独自条件があることと、runnora の自作コードを MIT で公開できることは別の問題です。Go の `go-ora` ドライバーを利用すること自体で Oracle Database の製品ライセンスがバイナリに移ることはありません。

## 文書用テンプレート

`api-test/docs/` と `grpc-test/docs/` には design-doc-quarto-template v2.4.0 由来の機構ファイルがあります。元の MIT 著作権名義 `RamsesYok` を含む本文を [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) に保持します。新しい自作部分の名義を ramsesyok に統一しても、元の表示は削除しません。
