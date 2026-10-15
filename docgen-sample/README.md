# runnora-docgen テストシナリオ表示サンプル

[runbook](runbooks/scenario.yml) と [生成した Quarto 原稿](docs/index.qmd) で、テストシナリオ表の表示を確認できます。`exec.command` は `runnora-diff` で同じ内容の JSON ファイルを比較します。

`runnora-docgen` と Quarto をインストールし、このフォルダで実行します。

```powershell
runnora-docgen generate --suite docgen --out docs/generated --force
quarto render docs --to html
```

PowerShell では `./scripts/build-docs.ps1` でも同じ操作ができます。PDF も更新する場合は `-Pdf` を付けます。`RUNNORA_DOCGEN_EXE` で実行ファイルを指定できます。

HTML は `docs/_book/index.html` にできます。[サンプル PDF](docs/design-doc.pdf) は `ddq pdf docs` で更新できます。runbook を実行する場合は `runnora` と `runnora-diff` を PATH に置き、`runnora run --suite docgen` を実行します。
