# 開発方針

## 構成

- Rails MVCで実装する。Serviceレイヤーは作らない。
- 気象データの取り込み処理は`app/models/weather`、外部HTTP通信は`lib/clients`に置く。
- ユーザー認証はまだ導入せず、`User#uuid`をURLに使う。
- アプリの日時・日付境界は`Asia/Tokyo`。

## 進め方

- TDDで、失敗するテスト、実装、成功確認、整理の順に進める。
- 作業の区切りで`PARALLEL_WORKERS=1 bin/rails test`、`bin/rubocop --cache false`、`bin/rails zeitwerk:check`を実行する。
- 区切りごとに意味のあるコミットを作り、コミット後はIDと検証結果を共有する。
- 仕様は`.codex/pressure_condition_app_design.md`、作業順は`.codex/TODO.md`を正本とする。

## 主要な動作

- Location登録後に`WeatherBackfillJob`を予約し、Solid Queueの定期実行で`WeatherSyncJob`を毎時動かす。
- バックフィルは登録時刻の24時間前と、最古の体調ログの24時間前のうち早い方から取得する。
- 分析の日次表示は`realtime`、月次表示は`confirmed`を使う。
- 月次では基準時刻から24時間分のconfirmed気象データが揃わない体調ログを除外する。

## 資料の扱い

- セッションをまたぐ作業状態は`.codex/local/SESSION_HANDOFF.md`に記録する。
- 引き継ぎ資料は作業ツリーに残してよいが、コミットするかどうかはユーザーの指示に従う。
- 実装変更を行ったら、必要に応じて`.codex/TODO.md`と設計メモも同じ変更に合わせて更新する。
