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

## 実機結果（ビルド1、2026-10-17）
- 方式A：区間終了後も「前の区間 0:00」のまま。staleDate による先読み表示は出なかった（方式Bでも再描画は遅れたり起きなかったりで、頼れない）。
- 方式B：ロック中でも予約した Live Activity が予定時刻に始まった（無操作で区間表示が切り替わった）。予約中を含め同時5件が上限。終わった区間は残る。
- 通知：ロック中・YouTube全画面中ともに届いた。音声と Dynamic Island は未判定（画面収録が島を占有）。

## 実機結果（ビルド3〜5、2026-10-17）
- ロック画面と Dynamic Island のボタン（完了・一時停止・再開・スキップ）は、アプリが裏にあっても動く。
- 予約した Live Activity の開始時に、アプリは裏で30〜75ms動ける。その間に終わった区間の Live Activity を終了できる（ロック画面に溜まらない）。
- ただし裏からの新規予約は「Target is not foreground」で拒否される。予約は最大5件（運用は4件＋1枠空き）なので、サーバーなしで無操作で進めるのは、最後にアプリかボタンを操作した時点から4区間先まで。
- 方式C：行ごとの ProgressView(timerInterval:) は未来の区間でも自動で進む。未来の区間の Text(timerInterval:) は止まったままになる（ビルド4で表示方法を変更）。
- 音声（H）：YouTube 再生中も聞こえ、動画の音は小さくなる。消音スイッチONでは鳴らない。

## この版の中身（v2〜v4）

予定は2種類：「時間制の連続」（休憩・プランク等7区間→腕立て）と「回数制まじり」（休憩→腕立て→休憩→プランク→休憩→スクワット→休憩→レッグレイズ）。

| 方式 | 仕組み |
|---|---|
| A: 先読み | 1つのLive Activity。staleDateで次区間を出す（1回目で不発） |
| B: 区間ごと予約（iOS 26） | 自動で始まる区間ごとに予約。上限5件 |
| C: 予定表 | 1つのLive Activityに数区間を並べ、各行のタイマーとバーがOSの時計で進む。更新不要 |

- 各境界の5秒前に、カウントダウン音声（`App/Sounds/countdown5.wav`、Windows標準音声で作成した検証用素材）付き通知。A/Cは開始通知も。
- 操作のたびに `probe.` の予約・表示済み通知をすべて消して組み直す。回数制は自動完了しない。
- ログ：操作、区間更新、バックグラウンド移行、アプリ復帰時の状態（補正前）、アプリ起動（前面／バックグラウンド）、LA状態の変化。

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
