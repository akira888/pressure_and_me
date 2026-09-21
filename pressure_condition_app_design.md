# 気圧・体調トラッキングアプリ 設計メモ

このファイルを実装時の正本とする。過去の追記を含む版は
`pressure_condition_app_design_v3.md` として残す。

## 1. 目的

気圧・湿度などの気象変化と自分の体調の関係を、継続的に記録・分析する。

- 気圧上昇・下降のどちらで、どの程度の変化量で影響が出るか
- 気象変化から症状までの時間差（lag）があるか
- 睡眠、歩数、飲酒、画面時間などとの組み合わせがあるか
- 自分固有の体調悪化パターンを見つけられるか

絶対値の精密さより、同じ基準の時系列から変化量を追うことを重視する。

## 2. 基本方針

- 一次データは加工せず保存する。
- Δ3h・相関・ラグなどの分析値は初期段階では保存せず、一次データから都度算出する。
- 分析結果には割合と必ず母数を表示する。
- 初期版はユーザーごとに既定地点を1つだけ使う。
- 業務上の日時と日付境界は `Asia/Tokyo` を基準にする。
- 初期版のDBはSQLiteとする。

### DBの選択

初期版は、個人利用・少量の時系列データを早く使い始めることを優先し、SQLiteを使う。

- 日々の入力、毎時同期、初期の集計・ラグ分析はSQLiteで行う。
- SQLiteは同時に1つの書き込み処理しか実行できないため、書き込み処理は短いトランザクションに保つ。
- サーバーへ公開する場合は、SQLiteファイルを永続的に保存できるローカルディスクまたは永続ボリュームを使う。
- 複数ユーザーでの同時利用、複数プロセスでの頻繁な書き込み、重いDB内分析が必要になった時点でPostgreSQLへ移行する。
- 移行を容易にするため、初期実装ではDB固有のSQLに依存しない。

## 3. データモデル

すべてのモデルにはRails標準の `created_at` / `updated_at` を持たせる。

```text
User
 ├─ has_one  Location
 ├─ has_many ConditionLogs
 └─ has_many DailyLogs

Location
 └─ has_many WeatherSamples
```

### User

初期段階では薄いモデルとし、認証情報・名前・メールアドレスは持たせない。

### Location

| カラム | 型 | 用途 |
|---|---|---|
| user_id | bigint | 所有ユーザー |
| latitude | decimal | 緯度 |
| longitude | decimal | 経度 |

- `user_id`、`latitude`、`longitude` は NOT NULL。
- `locations.user_id` は UNIQUE INDEX。ユーザーごとに既定地点は1つだけとする。

### WeatherSample

| カラム | 型 | 用途 |
|---|---|---|
| location_id | bigint | 取得地点 |
| observed_at | datetime | 気象データの対象時刻 |
| data_kind | integer | `realtime` または `confirmed` |
| pressure_msl | decimal | 海面更正気圧 |
| temperature | decimal | 気温 |
| humidity | integer | 相対湿度（%） |
| precipitation | decimal | 降水量 |
| weather_code | integer | WMO Weather Code |

- `location_id`、`observed_at`、`data_kind` は NOT NULL。
- `(location_id, observed_at, data_kind)` に UNIQUE INDEXを置く。
- 同一地点・同時刻の即時データと確定データは併存させる。
- 同じ地点・時刻・データ種別の再取得は upsert する。

### ConditionLog

入力した瞬間の状態を表すスナップショット。朝・夕の定期入力に限らず、何度でも追加する。

| カラム | 型 | 用途 |
|---|---|---|
| user_id | bigint | 記録したユーザー |
| recorded_at | datetime | 記録時刻 |
| headache | integer | 頭痛 1〜10 |
| nausea | integer | 気持ち悪さ 1〜10 |
| fatigue | integer | だるさ 1〜10 |
| appetite | integer | 食欲 1〜10 |
| clarity | integer | 頭のクリアさ 1〜10 |

- 全カラムは NOT NULL。各スコアは1〜10。
- `(user_id, recorded_at)` にINDEXを置く。`recorded_at` はUNIQUEにしない。
- 同じ時刻の複数レコードを許容し、常にINSERTする。
- 症状系の `1` は「なし／ほぼなし」、`10` は「とても強い」。
- `appetite` と `clarity` は、`10` がそれぞれ「とてもある」「とてもクリア」。必要なら分析時に方向を変換する。

### DailyLog

朝に入力する、ユーザーごとに1日1件のログ。`date` は入力した朝の日付とする。

| カラム | 型 | 用途 |
|---|---|---|
| user_id | bigint | 記録したユーザー |
| date | date | 入力した朝の日付 |
| wakeup_freshness | integer | 朝スッキリ起きられたか 1〜10 |
| sleep_minutes | integer | 前夜から当朝までの睡眠時間 |
| steps | integer | 前日の歩数 |
| drank_alcohol | boolean | 前日の飲酒有無 |
| screen_minutes | integer | 前日のモニター時間 |

- 全カラムは NOT NULL。
- `wakeup_freshness` は1〜10、`sleep_minutes`・`steps`・`screen_minutes` は0以上。
- `(user_id, date)` にUNIQUE INDEXを置く。
- 同じユーザー・日付を再入力した場合はUPDATEする。

## 4. 気象データの取得

Open-Meteoから1時間粒度で取得する。取得地点には `Location.latitude` / `Location.longitude` を使い、`timezone=Asia/Tokyo` を指定する。

共通の hourly パラメータ:

```text
temperature_2m, relative_humidity_2m, precipitation, pressure_msl, weather_code
```

同じ時刻・地点に対して、即時性と確定性のための2系列を保存する。

| `data_kind` | 用途 | API・モデル |
|---|---|---|
| `realtime` | 日々の確認・日次分析 | Forecast API、`models=jma_seamless` |
| `confirmed` | 月次など蓄積データの分析 | Historical Weather API、`models=ecmwf_ifs` |

- `realtime` は予報モデル由来の値を含む即時データ。
- `confirmed` は履歴APIが返す利用可能な時刻だけを保存する。取得の遅延を固定日数で仮定しない。
- `confirmed` の取得後も `realtime` を更新・削除しない。

### 取得処理

Active Job + Solid Queueを使い、同期的なAPI呼び出しでアプリ起動や画面表示を待たせない。

```text
WeatherBackfillJob / WeatherSyncJob
  └─ 地点・data_kindごとに取得期間を決定
      └─ Weather::Importer.call(location:, from:, to:, data_kind:)
          └─ Clients::OpenMeteoClient
              └─ Open-Meteo API
```

- 初回バックフィルは過去7日分を対象に、`realtime` と `confirmed` の両方を取得する。
- `confirmed` はAPIが返す利用可能な時刻だけを保存する。
- 以降は地点・`data_kind`ごとに最新の `observed_at` 以降を差分取得する。
- `WeatherSyncJob` は毎時実行し、データ種別ごとに直近期間の欠損も検査・再取得する。
- `WeatherSyncJob` は最新サンプルを下限にする。ただし直近24時間を再取得範囲に含め、
  最新サンプルが新しい場合も欠損を再検査する。系列が空の場合は過去7日分を対象にする。
- `Weather::Importer` は取得期間の決定をせず、指定範囲を取得・整形・upsertする。
- `Clients::OpenMeteoClient` はHTTP通信、パラメータ構築、`data_kind`ごとのエンドポイント・モデル選択、レスポンス整形だけを担う。DBを知らない。

配置:

```text
app/models/weather_sample.rb
app/models/weather/importer.rb
app/jobs/weather_backfill_job.rb
app/jobs/weather_sync_job.rb
lib/clients/open_meteo_client.rb
```

## 5. 入力画面

画面上部に `[ 体調 ] [ 朝の記録 ] [ 分析 ]` の3タブを置き、初期表示は「体調」とする。

### 体調

- `headache`、`nausea`、`fatigue`、`appetite`、`clarity` を1〜10のスライダーで入力する。
- 前回のConditionLog値を初期値にする。
- `recorded_at` の基本値は現在時刻。
- 保存するまで記録は作らない。

### 朝の記録

- `wakeup_freshness` は初期値5の1〜10スライダー。前日値は引き継がない。
- `sleep_minutes` と `screen_minutes` は画面上では「時間」「分」で入力し、DBには総分数で保存する。
- `steps` は数値入力、`drank_alcohol` はYes / Noの二択。

## 6. 分析

### 基準時点

ConditionLogが任意時刻でも未来の気象値は使わない。記録時刻以前で最も新しい毎正時のWeatherSampleを基準とする。

```text
ConditionLog: 10:37
基準WeatherSample: 10:00
Δ3h: 10:00 と 07:00 の差
```

分析では `data_kind` を1つ選び、その系列のみで計算する。`realtime` と `confirmed` を混在させない。

- 日々の振り返り、日次分析: `realtime`
- 月次など蓄積データの分析: `confirmed`
- 月次分析では、必要な24時間分の確定データが揃わない直近の状態ログを除外する。

### 指標

状態ログを基準に、以下を一次データから都度算出する。

- 基準時点の気圧
- Δ3h、Δ6h、Δ12h、Δ24h
- 直近6h・24hの気圧レンジ
- 期間内の最大1時間上昇量・下降量
- 上昇／下降の継続状態、急変終了後からの経過時間
- lag 0h、3h、6h、12h

```text
Δ6h = P(t) - P(t - 6h)
```

負値は気圧低下、正値は気圧上昇を表す。

### 見る観点

- 相関: 例）Δ6h気圧 × だるさ
- 閾値: 例）6時間で3hPa以上下降したときに、だるさ7以上となる割合
- 時間差（lag）
- 波形: 下降中、底付近、上昇中、急変終了後
- 複合条件: 気圧急下降＋睡眠不足など
- ベースライン比較: まずは全ConditionLogの分布を基準にし、母数を併記する

初期画面は「時系列」「最近の記録」「傾向」で構成する。

## 7. 初期段階で後回しにするもの

- 分析結果専用テーブル、分析結果の永続化
- 機械学習、高度な予測モデル、自動的な因果判定
- 多変量分析と、統計的に十分な件数の厳密な判定
- キャッシュ、集計テーブル、materialized view

分析処理が重くなった場合にのみ、これらを検討する。

## 8. 実装時に決める詳細

- 起動時にBackfillJobをenqueueする方法
- グラフライブラリ
- 分析期間、症状閾値の初期値

### Phase 2で採用した実装詳細

- 緯度・経度は `decimal(10, 6)`、気圧・気温・降水量は `decimal(12, 6)`。
- `data_kind` は `realtime: 0`、`confirmed: 1` に固定し、ModelとDB双方で他の値を拒否する。
- スコアは1〜10の整数、分数・歩数は0以上の整数をModelとDB双方で検証する。
- 飲酒有無は `false` も有効な回答とし、未回答の `NULL` は許容しない。
- 気象値の欠損は `NULL` で保存できる。値がある場合はModelで数値型を検証する。
- 関連レコードがあるUser・Locationの削除は制限し、暗黙の連鎖削除を行わない。
- 制約はRailsのmigration APIと標準SQLの比較・`IN`・`CAST`で定義する。
  PostgreSQLでの動作確認は移行時に行う。

### Phase 3で採用した実装詳細

- Serviceレイヤーは設けず、`Weather::Importer` は `app/models/weather`、
  `Clients::OpenMeteoClient` は `lib/clients` に置く。
- `Weather::Importer.call(location:, from:, to:, data_kind:)` は保存済みLocationと
  両端を含む時刻範囲を受け取り、対象サンプル数を返す。期間の自動決定は行わない。
- クライアントは `fetch(latitude:, longitude:, from:, to:, data_kind:)`。
  `from` / `to` はTimeまたはActiveSupport::TimeWithZoneで指定する。
  APIには東京日付の `start_date` / `end_date` を渡し、返却後に指定時刻範囲へ絞る。
- HTTPは標準のNet::HTTPを使用。接続5秒・読み取り15秒・書き込み5秒のタイムアウトを設定する。
  クライアント内の自動リトライは行わず、Phase 4でジョブ側の再実行を扱う。
- 通信失敗は `TransportError`、HTTP失敗はステータスを持つ `HTTPError`、
  不正なJSON・配列長・時刻・数値は `InvalidResponse` として通知する。
- 部分的な欠損はNULLで保持する。全気象項目がNULLの時間は保存せず、
  再取得が全項目NULLだった場合も既存の観測値は削除しない。
- 全レスポンスの変換・検証を終えてから、単一の `upsert_all` で保存する。
  同一キーの気象値を更新し、ID・作成日時と他の地点・系列は保持する。
  部分的な欠損を含む有効な再取得結果は、そのNULLも含めて更新する。
- HTTP境界を差し替えた固定レスポンスで、外部APIに依存しない自動テストを行う。

### Phase 4で採用した実装詳細

- `WeatherBackfillJob` は全Locationについて`realtime`と`confirmed`を7日間取得する。
- `WeatherSyncJob` は全Location・系列について、`min(最新サンプル, 現在時刻-24時間)`から現在時刻までを取得する。
  サンプルがない系列は現在時刻から7日前を下限にする。
- 両ジョブは`weather`キューに入り、Importerの冪等upsertにより再実行できる。
- Solid Queueの`config/recurring.yml`でdevelopment/productionとも毎時`WeatherSyncJob`を起動する。

2026-09-21に確認した[公式Historical Weather API仕様](https://open-meteo.com/en/docs/historical-weather-api)では、
ECMWF IFSは毎時データ・6時間ごとの更新・遅延なしと記載されている。
以前の「約2日遅れ」という想定は撤回し、利用可能性は実際のレスポンスで判断する。
`confirmed` はこのアプリ内の履歴系列の名称であり、観測の確定値や不変性を保証する名称ではない。
日付範囲・単位・タイムゾーンは[Forecast API仕様](https://open-meteo.com/en/docs)も参照する。
