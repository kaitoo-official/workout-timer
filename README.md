# 筋トレタイマー iPhone検証版（workout-timer / probe）

本体とは別のSwiftUI実験アプリ。目的は「画面外・無操作でどこまで進行と表示切替ができるか」をiPhone実機で判定すること。
元の作業案（ChatGPTプロジェクト output/workout-timer/ios-probe）をコピーし、レビュー・修正したもの。Pocket Baseの設定は参照のみ。

## 前提（Apple公式資料の調査結果 2026-10-16）

- アプリが止まっている間に、任意の時刻でLive Activityを更新する公式APIはない。
  自動で変わるのは「タイマー表示（Text(timerInterval:)）」と「staleDate到達時のisStale」だけ。
- 予約通知の配信はアプリを起動しない。BGTaskSchedulerは時刻を保証しない。
- LiveActivityIntent（Live Activity上のボタン）は、アプリをバックグラウンドで起動して実行される。
- iOS 26から `Activity.request(...start:)` でLive Activityを指定時刻に開始する予約ができる（アラート設定必須、同時数上限に数える）。
- 確実な無操作更新はActivityKitのAPNsプッシュ（サーバー必要）。AlarmKitは区間ごとに消音・集中モードを破るアラームになり用途が合わない。
- 不要な音声再生やHealthKitで実行を維持する方法は使わない。

## この版の中身

予定：休憩20秒 → プランク20秒 → 休憩20秒 → サイドプランク右20秒 → 左右間の休憩20秒 → サイドプランク左20秒 → 休憩20秒 → 腕立て15回（回数制）

サーバーなしの2方式を切り替えて比較する。

| 方式 | 仕組み | 期待と限界 |
|---|---|---|
| A: 1つのLA＋先読み | 1つのLive Activity。区間終了（staleDate）で、内容に入れておいた「次の区間」を表示 | アプリ無実行でも1区間分だけ切替可能な見込み。2区間目以降は止まるはず |
| B: 区間ごと予約LA（iOS 26） | 開始時に、自動で始まる区間ごとにLive Activityを予約。終わった区間は「終了」表示 | 各区間の開始はOSが行う。同時数上限・表示の重なり・アラートの出方を確認 |

- 各境界の5秒前に、カウントダウン音声（`App/Sounds/countdown5.wav`、Windows標準音声で作成した検証用素材）付き通知を予約。
- 方式Aは境界ごとに「開始」通知も予約。方式BはLive Activityのアラートで知らせる。
- 一時停止・スキップ・完了・終了のたびに、`probe.` で始まる予約／表示済み通知をすべて消してから組み直す。
- 回数制（腕立て）は自動完了しない。完了ボタンで終了。
- アプリ内ログ：操作・区間更新・バックグラウンド移行・「アプリ復帰時」のLive Activity状態と予約通知件数を記録。
  **復帰時の記録はアプリが補正する前の状態**。復帰後に正しく表示されても自動切替の成功にはしない。

## Codemagic

- `compile-probe`：署名なしでアプリと拡張をコンパイル（Xcode 26.6、xcodegenはbrewで導入）。
- `setup-signing`（一度だけ実行済み）：App Store Connect API（既存の `pocket-base-asc` キー）で
  Bundle ID `com.kaitooofficial.workoutprobe`／拡張 `com.kaitooofficial.workoutprobe.activity` を登録し、App Store用プロファイルを作成。作成のみで削除・失効はしない。
- 署名：Codemagic の Code signing identities に、新規作成した配布証明書 `workout-probe-distribution` と
  プロファイル `workout-probe-appstore`／`workout-probe-activity-appstore` を保管（Pocket Base の `ios_signing` グループはアプリ単位で共有不可のため使わない）。
- `signed-probe`：上記で署名し App Store Connect へアップロードのみ。外部テスト審査・App Store審査には出さない。
- App Store Connect に上記IDで検証用アプリを事前登録する必要がある（APIでは作れない）。

## 合格判定（実機 iPhone 15 Pro / iOS 26.6.2）

| | 判定 | 確認方法 |
|---|---|---|
| A | クラウドでアプリと拡張がコンパイル | compile-probe成功＋PlugIns内に拡張 |
| B | TestFlightからインストール | 内部テストでインストール・起動 |
| C | Dynamic Island・ロック画面に時間と操作 | 表示・ボタンの反応 |
| D | YouTube再生中・ロック中に通知 | 5秒前と開始の通知時刻 |
| E | 無操作で時間制の区間とLA表示が次々切替 | 方式A/Bそれぞれ。復帰時ログで判定 |
| F | 一時停止・スキップ・終了後に古い通知が残らない | 操作後の通知の有無とログの予約件数 |
| G | 回数制は勝手に完了しない | 腕立てで放置 |
| H | 最後5秒の音声がYouTube再生中にどう鳴るか | 音量・動画音声への影響・消音時 |

A〜Dだけで全要件達成とはしない。Eが方式A/Bで満たせない場合、APNsプッシュ（サーバー）案を費用付きで相談する。

## 参照
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit
- https://docs.codemagic.io/specs-macos/xcode-26-6/
