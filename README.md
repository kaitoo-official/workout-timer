# workout-timer

自分のメニューを順番に回す筋トレタイマー（iOS・SwiftUI、iOS 26以降）。アプリ名は未確定。

| 場所 | 中身 |
|---|---|
| `Packages/WorkoutCore/` | 進行の中心部（メニュー、区間、セッション、制限判定、Live Activity・通知の予約計画、保存）。画面やOSに依存せず `swift test` で検証できる |
| `docs/メニュー形式.md` | 保存データの形式（Android でも同じ形式を使う前提） |
| `docs/動作ルール.md` | 進行・操作・制限判定・表示・通知・保存のルールと保証範囲 |
| `probe/` | 2026-10-17 に実機で合格した検証版（ビルド6）。仕組みの根拠として残す |
| `codemagic.yaml` | `core-tests`（単体テスト）、`compile-probe` / `setup-signing` / `signed-probe`（検証版） |

本体アプリ（画面・Live Activity 拡張）は 2週目以降に追加する。
