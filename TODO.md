# 実装TODO

このTODOは [設計メモ](pressure_condition_app_design.md) を正本として実装を進めるための作業順です。
設計を変更する必要がある場合は、実装前に設計メモを更新して合意する。

## 開発の進め方

- Serviceレイヤーを作らずMVCで構成する。取り込み処理はModel側、外部HTTP通信は `lib/clients` に置く。
- TDDで、失敗するテストの確認→実装→テスト成功→整理の順に進める。
- Phase完了などの作業の区切りで、必要な検証とTODO更新を行い、Gitにコミットする。
- コミット後は、コミットIDと実装・検証結果を共有する。

## 現在の状態

- [x] 設計メモを整理し、正本を `pressure_condition_app_design.md` に統合
- [x] ユーザー、既定地点、即時／確定気象データの方針を確定
- [x] Gitリポジトリの初期化（mainブランチ）
- [x] Railsアプリの作成

## Phase 1: アプリ基盤

- [x] RailsアプリをSQLite構成で作成する
- [x] Active JobとSolid Queueを設定する
- [x] アプリケーションのタイムゾーンを `Asia/Tokyo` に設定する
- [x] SQLiteのWALモードとbusy timeoutを開発・デプロイ環境で設定する
- [x] ローカル開発の起動・DB作成手順をREADMEに記載する

完了条件: Railsアプリがローカルで起動し、ジョブ基盤とSQLiteへ接続できる。

確認済み: 初期画面と `/up` のHTTP 200、Solid Queueワーカーでの一時ジョブ完了、
開発・本番設定のDB接続とWAL・timeout 5000ms。実際のデプロイは未実施。

## Phase 2: データモデル

- [x] `User`、`Location`、`WeatherSample`、`ConditionLog`、`DailyLog` のmigrationを作成する
- [x] 外部キー、NOT NULL、チェック制約、ユニークインデックスを設計メモどおりに設定する
- [x] `WeatherSample.data_kind` に `realtime` / `confirmed` のenumを設定する
- [x] モデルの関連とvalidationを実装する
- [x] モデル・制約のテストを作成する
- [x] DB固有のSQLに依存しないことを確認する

完了条件: ユーザーごとの既定地点、各ログ、2種類の気象時系列を矛盾なく保存できる。

確認済み: SQLite上のモデル・DB制約テスト72件（295 assertions）。
直接SQLによる制約検証と、気象データの系列を分離したupsertの冪等性を含む。
同日DailyLogを検索して更新するフォーム処理はPhase 5で実装する。

## Phase 3: 気象データの取り込み

- [x] `Clients::OpenMeteoClient` を実装する
- [x] `Weather::Importer` を実装する
- [x] `realtime`（Forecast API / JMA）を取得・upsertする処理を実装する
- [x] `confirmed`（Historical Weather API / ECMWF IFS）を取得・upsertする処理を実装する
- [x] APIレスポンスの変換、失敗時の扱い、冪等性をテストする

完了条件: 任意の既定地点に対し、2種類の毎時気象データを安全に保存できる。

確認済み: クライアント14件・取り込み11件をテスト先行で追加。
東京駅付近の公開座標で、両APIから2026-09-14の24時間分を実取得し、変換まで確認。
実APIの確認ではDB保存を行わず、自動テストは固定レスポンスでネットワークから独立させる。

## Phase 4: 非同期ジョブと同期

- [ ] `WeatherBackfillJob` を実装する
- [ ] `WeatherSyncJob` を実装する
- [ ] 初回7日分のバックフィルを実装する
- [ ] 地点・データ種別ごとの差分取得と欠損再取得を実装する
- [ ] Solid Queueの毎時recurring taskを設定する
- [ ] ジョブ再実行・期間重複のテストを追加する

完了条件: 起動時バックフィルと毎時同期が、重複データを作らずに動作する。

## Phase 5: 記録画面

- [ ] 体調入力フォームを実装する
- [ ] 朝の記録フォームを実装する
- [ ] DailyLogの同日UPDATEを実装する
- [ ] スコア、分数、数値、必須入力の画面上のvalidationを実装する
- [ ] 3タブの基本画面を実装する

完了条件: 体調ログを何度でも追加でき、朝の記録をユーザーごとに1日1件更新できる。

## Phase 6: 初期分析画面

- [ ] 状態ログ時刻以前の直近毎正時WeatherSampleを選ぶ処理を実装する
- [ ] Δ3h / Δ6h / Δ12h / Δ24h と気圧レンジを算出する
- [ ] 日次では `realtime`、月次では `confirmed` のみを使うようにする
- [ ] 月次分析で確定気象データが不足する状態ログを除外する
- [ ] 時系列、最近の記録、傾向の初期画面を実装する
- [ ] 割合と母数を併記する集計を実装する

完了条件: 少量のデータでも、個別の状態ログと直前の気象変化を確認できる。

## 後回し

- [ ] 相関、閾値、lag、複合条件の高度な分析
- [ ] キャッシュ、集計テーブル、materialized view
- [ ] 機械学習・予測・因果判定
- [ ] 認証情報、複数地点、複数ユーザー向けの画面
