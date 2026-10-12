# grpc-sim-test：ランダム終了の gRPC Server streaming

指定空間内の等半径球を Go サーバで移動させ、壁での反射と物体同士の衝突を `ExecSimulation` で逐次配信します。５ステップ分のログを１つの `SimResponse` にまとめ、終了時の端数も送ります。runnora の runbook は終了ステップ数を入力せず、受信した全ログに対して性質を検証します。

## 実行

Go 1.24 以降と、隣接する `../runnora` リポジトリが必要です。PowerShell から以下を実行します。

```powershell
cd grpc-sim-test
./scripts/run.ps1
```

スクリプトはサーバと runnora をビルドし、サーバを `127.0.0.1:19091` で起動してスイート `grpc-sim` を実行します。`RUNNORA_EXE` に実行ファイルを指定することもできます。終了時にはサーバを停止します。runnora のレポートと各 RPC の全受信メッセージは `reports/<日時>-grpc-sim/` に保存されます。

`./scripts/build-docs.ps1` は runnora-docgen と Quarto で [HTML 手順書](docs/index.qmd)を生成します。原稿だけを更新する場合は `-GenerateOnly` を指定します。

手動での実行は別ターミナルで `go run ./cmd/simd -proto proto/simulation.proto` を起動し、`runnora run --suite grpc-sim` を実行します。

## 契約と物理モデル

[proto/simulation.proto](proto/simulation.proto) は依頼のインターフェースをもとに作成しました。未定義だった綴りを `Poition` → `Position`、`hist` → `hit` に修正しています。サーバはこの proto を起動時に読み込むため `protoc` は不要です。

- `direction` は +X から +Y への角度（度）です。移動は XY 平面内で、Z 座標は変わりません。衝突するのは同じ Z 平面の球だけです。
- 全物体の半径は 0.5 座標単位、質量は等しく、1 ステップはシミュレーション時刻 1000 単位です。サーバは約 40 ms ごとに１ステップ進め、通常５ステップごとに配信します。`timestamp` は壁時計ではなくシミュレーション時刻です。
- 壁に達すると速度成分を反転し、`event_type=2` と `reflect` を記録します。球同士が接近して接触すると等質量の弾性衝突を計算し、`event_type=1` と `hit` を記録します。`hit_count` は衝突イベントの合計です。
- サーバはリクエスト受付後に 8〜12 ステップをランダムに選びます。選ばれたステップ数は返しません。途中の `progress` は終了時刻から計算した割合ではなく、レスポンス内の最後のログ時点での推定値です。最終レスポンスでのみ 1 になります。
- 通常のレスポンスは５件の `SimLog` を含み、最後は残りの１〜５件を含みます。8〜12 ステップならレスポンスは２〜３件です。各 `SimLog` に全物体の `ObjectLog` が入ります。途中の `result` は未設定、最後のレスポンスだけ `result` を設定します。runnora の受信 JSON では `int64` が文字列になり、ゼロ値の `exit_code` と `hit_count` も `"0"` として参照できます。

## runbook の検証

| runbook | 検証 |
|---|---|
| [collision.yml](runbooks/collision.yml) | ２物体の衝突と反射が発生し、５ログ単位と最終端数、進捗・時刻・位置が整合する。最後の `hit_count` が全ログの衝突イベント数と一致する |
| [reflection.yml](runbooks/reflection.yml) | 単一物体では反射だけが起き、衝突はゼロ。５ログ単位で受信し、最後だけ `result` がある |
| [invalid-area.yml](runbooks/invalid-area.yml) | 上下限が逆の空間を拒否し、gRPC `InvalidArgument`（コード 3）でメッセージを送らない |
| [numeric-basic.yml](runbooks/numeric-basic.yml) | 単一物体の定速移動を終了まで受信し、各 `SimResponse.logs` と最終 `result` を `diffEps()` で期待 JSON と照合する |

正常系は**終了ステップ数を固定せず**、8〜12 ログという境界、５件ごとのレスポンス、全ログの時刻順、レスポンス間の進捗を検証します。`timeout: 10s` はストリームが終了しない場合の安全上限です。検証失敗時も runnora の証跡に受信済みメッセージが残ります。

基本的な数値結果比較では [期待ログ](cases/numeric-basic/expected-logs.json)の X 座標を実値より `0.0004` 大きくし、[許容誤差](cases/numeric-basic/tolerances.yaml)の絶対誤差 `0.001` 内で比較します。期待値は最大12ステップ分用意し、サーバが実際に送った各レスポンスのログ数に合わせて該当部分を比較します。[最終結果](cases/numeric-basic/expected-result.json)は `exit_code` と `hit_count` の整数値で、同じ `diffEps()` を用いて照合します。
