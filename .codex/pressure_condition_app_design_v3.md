# 気圧・体調トラッキングアプリ 設計メモ

## 目的

気圧や湿度などの気象変化と、自分の体調との関係を継続的に記録・分析する。

特に知りたいことは以下。

- 気圧変化と体調悪化に関連があるか
- 上昇・下降のどちらで影響が出やすいか
- どの程度の変化量・急変で影響が出るか
- 気象変化から何時間後に症状が出やすいか
- 睡眠・歩数・飲酒・モニター時間など、他要因との組み合わせがあるか
- 将来的に、自分固有の体調悪化パターンを見つけられるか

絶対気圧の正確さそのものよりも、一定の基準に基づいた時系列データから
「変化量」を追跡できることを重視する。


## データ方針

一次データはできるだけ加工せず保存する。

分析結果や以下のような二次データは、初期段階ではDBに保存しない。

- 3時間気圧変化
- 6時間気圧変化
- 12時間気圧変化
- 24時間気圧変化
- 上昇中 / 下降中
- 最大下降速度
- 最大上昇速度
- 各症状との相関
- ラグ別の分析結果

これらは一次データから都度計算する。

分析処理が重くなった場合は、将来的にキャッシュや分析テーブルの導入を検討する。


## 気象データ

Open-Meteo を利用する。

1時間ごとに保存する想定。

### WeatherSample

| カラム | 型 | 用途 |
|---|---|---|
| location_id | bigint | 気象データを取得した地点 |
| observed_at | datetime | 気象データの対象時刻 |
| data_kind | integer | `realtime` または `confirmed` |
| pressure_msl | decimal | 海面更正気圧 |
| temperature | decimal | 気温 |
| humidity | integer | 相対湿度（%） |
| precipitation | decimal | 降水量 |
| weather_code | integer | WMO Weather Code |
| created_at | datetime | Rails標準 |
| updated_at | datetime | Rails標準 |

### 制約

- `location_id`: NOT NULL
- `observed_at`: NOT NULL
- `data_kind`: NOT NULL
- `(location_id, observed_at, data_kind)`: UNIQUE INDEX

即時データと確定データは同じ地点・同じ時刻でも併存させる。
同じ `data_kind` のデータを再取得した場合は、重複INSERTではなく upsert / update できる構造にする。

### 気象データの種別

即時性と確定性の両方を扱うため、同一の地点・時刻について以下の2種類を保存する。

| `data_kind` | 用途 | Open-Meteoの取得元 |
|---|---|---|
| `realtime` | 日々の確認・日次分析 | Forecast API、`models=jma_seamless` |
| `confirmed` | 月次など蓄積データの分析 | Historical Weather API、`models=ecmwf_ifs` |

- `realtime` は直近の状況を確認するための即時データであり、予報モデル由来の値を含む。
- `confirmed` は履歴APIで取得できるデータを保存する。リアルタイムから約2日遅れて利用可能になる想定とし、APIから返った時刻だけを保存する。
- `confirmed` を取得しても `realtime` を上書き・削除しない。2種類の時系列を併存させる。
- 日次の確認・分析は `realtime` を使う。月次などの蓄積データを対象にする分析は `confirmed` を使う。

### 時刻方針

- ユーザーに表示する日時と `DailyLog.date` の日付境界は `Asia/Tokyo` を基準にする。
- Open-Meteoには `timezone=Asia/Tokyo` を指定する。
- `ConditionLog` の任意時刻に対しては、未来の値を使わず、記録時刻以前で最も新しい毎正時の `WeatherSample` を基準にする。

例: 10:37 の状態ログは 10:00 を基準とし、Δ3h は 07:00 の値との差として算出する。

### 保存しない分析値

気圧については生の時系列を残し、以下は分析時に算出する。

- Δ3h
- Δ6h
- Δ12h
- Δ24h
- 期間内の最大1時間下降量
- 期間内の最大1時間上昇量
- 上昇 / 下降の継続状態
- 急変終了後から状態ログまでの経過時間


## 状態ログ

「午前」「午後」のような区分ではなく、
**入力したその瞬間の状態のスナップショット**として記録する。

朝・夕など定期的に入力するほか、つらいときには何度でも追加登録できる。

### ConditionLog

| カラム | 型 | 用途 |
|---|---|---|
| user_id | bigint | 記録したユーザー |
| recorded_at | datetime | 状態を記録した時刻 |
| headache | integer | 頭痛 1〜10 |
| nausea | integer | 気持ち悪さ 1〜10 |
| fatigue | integer | だるさ 1〜10 |
| appetite | integer | 食欲 1〜10 |
| clarity | integer | 頭のクリアさ 1〜10 |
| created_at | datetime | Rails標準 |
| updated_at | datetime | Rails標準 |

### スコアの方向

入力時の直感を優先し、各項目は「その状態の強さ / 高さ」を1〜10で表す。

例:

- 頭痛 10 = とても強い
- 頭痛 1 = なし／ほぼなし
- だるさ 10 = とても強い
- だるさ 1 = なし／ほぼなし
- 食欲 10 = とてもある
- 頭のクリアさ 10 = とてもクリア

分析時に必要であれば方向を変換する。

### 制約

- `user_id`: NOT NULL
- `recorded_at`: NOT NULL
- `(user_id, recorded_at)`: INDEX
- 各スコア: NOT NULL、1〜10

`recorded_at` は UNIQUE にしない。

状態ログは毎回INSERTし、同じ時刻に複数レコードが存在してもDB上は許容する。


## 1日1回ログ

朝に入力する。

日付は「入力した朝の日付」を基準にする。

例: 2026-09-06 の DailyLog

- wakeup_freshness: 9/6朝の状態
- sleep_minutes: 9/5夜〜9/6朝の睡眠
- steps: 9/5の歩数
- drank_alcohol: 9/5の飲酒
- screen_minutes: 9/5の画面時間

「前日のデータだから前日の日付を付ける」とはせず、
各カラムの意味として前日の出来事を表現する。

### DailyLog

| カラム | 型 | 用途 |
|---|---|---|
| user_id | bigint | 記録したユーザー |
| date | date | 朝に入力した日 |
| wakeup_freshness | integer | 朝スッキリ起きられたか 1〜10 |
| sleep_minutes | integer | 昨晩の睡眠時間 |
| steps | integer | 前日の歩数 |
| drank_alcohol | boolean | 前日の飲酒有無 |
| screen_minutes | integer | 前日のモニター時間 |
| created_at | datetime | Rails標準 |
| updated_at | datetime | Rails標準 |

### 制約

- `user_id`: NOT NULL
- `date`: NOT NULL
- `(user_id, date)`: UNIQUE INDEX
- `wakeup_freshness`: NOT NULL、1〜10
- `sleep_minutes`: NOT NULL、0以上
- `steps`: NOT NULL、0以上
- `drank_alcohol`: NOT NULL
- `screen_minutes`: NOT NULL、0以上

`(user_id, date)` が UNIQUE なのは、「ユーザーごとに1日につき1レコード」というドメイン上の制約。
再入力時は新規作成ではなくUpdateする。


## 入力画面

初期段階では2画面。

### 1. 1日1回フォーム

朝に入力する。

- 朝スッキリ起きられたか
- 昨晩の睡眠時間
- 前日の歩数
- 前日の飲酒有無
- 前日のモニター時間

### 2. 状態登録フォーム

その瞬間の状態を入力する。

- 頭痛
- 気持ち悪さ
- だるさ
- 食欲
- 頭のクリアさ

何度でも登録可能。


## 分析方針

### 1. 個別ログの振り返り

状態ログを基準に、その前の気象変化を見る。

日々の振り返りでは `realtime` を使う。月次など確定データを対象にした振り返りでは `confirmed` を使い、必要な24時間分の確定気象データが揃わない直近の状態ログは集計対象から除外する。

例:

- 状態ログ時点の気圧
- 3時間前との差
- 6時間前との差
- 12時間前との差
- 24時間前との差
- 直近の急上昇 / 急下降
- 急変から状態ログまでの時間差

データが少ない初期段階から利用可能。


### 2. 蓄積データから傾向を探す

将来的に以下を分析する。

#### 相関

例:

- Δ6h気圧 × だるさ
- Δ12h気圧 × 頭痛
- Δ6h湿度 × 気持ち悪さ

Pearson相関などは入口として使うが、相関だけでは判断しない。


#### 閾値

例:

「6時間で3hPa以上下降した場合に、だるさ7以上になる割合」

単純な線形相関では見つけられないパターンを探す。


#### 時間差（ラグ）

例:

気圧急下降から

- 直後
- 3時間後
- 6時間後
- 12時間後

のどこで症状が強くなるかを見る。


#### 気圧波形

単純な変化量だけでなく、

- 下降中
- 底付近
- 上昇中
- 急変終了後

のどの局面で症状が出るかも将来的に分析する。


#### 複数要因

例:

- 気圧急下降 + 睡眠不足
- 高湿度 + モニター時間長め
- 飲酒翌日 + 気圧上昇

などの組み合わせを探す。


## ベースライン

「通常時」を最初から人為的に定義しない。

まずは自分自身の全状態ログをベースラインにする。

例:

- 全ログで「だるさ7以上」: 32%
- 特定条件時に「だるさ7以上」: 75%

この差を見る。

分析結果では割合だけでなく、必ず母数も表示する。

例:

- 12 / 16 = 75%
- 全体では 32 / 100 = 32%

将来的には、データ量が増えたら時間帯別ベースラインなども検討する。


## 初期段階では後回しにするもの

- 分析結果専用テーブル
- 分析結果の永続化
- 機械学習
- 高度な予測モデル
- 自動的な因果判定
- 「何件あれば十分か」の厳密な統計基準
- 気圧以外の要因を含めた多変量分析

まずは一次データを安定して収集できる形を作る。


## 現時点のモデル構成

```ruby
User
  id               :bigint

Location
  user_id          :bigint
  latitude         :decimal
  longitude        :decimal

WeatherSample
  location_id      :bigint
  observed_at      :datetime
  data_kind        :integer # realtime / confirmed
  pressure_msl     :decimal
  temperature      :decimal
  humidity         :integer
  precipitation    :decimal
  weather_code     :integer

ConditionLog
  user_id          :bigint
  recorded_at      :datetime
  headache         :integer
  nausea           :integer
  fatigue          :integer
  appetite         :integer
  clarity          :integer

DailyLog
  user_id           :bigint
  date              :date
  wakeup_freshness  :integer
  sleep_minutes     :integer
  steps             :integer
  drank_alcohol     :boolean
  screen_minutes    :integer
```


## Open-Meteo取得設計

### 基本方針

気象データ取得は同期処理にせず、Active Job + Solid Queue で非同期実行する。

アプリ起動時にはバックフィルJobをenqueueするだけとし、
Open-Meteo APIの応答待ちでアプリ起動や初回アクセスを遅らせない。

### 初回バックフィル

初回は過去7日分の気象データを、即時・確定の両方について取得する。
確定データは、履歴APIから返却された利用可能な時刻だけを保存する。

```text
初回起動
  ↓
WeatherBackfillJob enqueue
  ↓
過去7日〜現在までの即時データを取得
  ↓
過去7日〜履歴APIで取得可能な時刻までの確定データを取得
  ↓
WeatherSampleへupsert
```

以降は地点・`data_kind` ごとに `WeatherSample.maximum(:observed_at)` を基準に、
不足している期間だけ取得する。

### 定期取得

1時間ごとに定期取得する。

Solid Queue の recurring task を利用する想定。

### Jobの責務

Jobは「どの期間を取得するか」を決める。

```text
WeatherBackfillJob
  └─ 地点・data_kindごとに初回7日分または不足期間を決定
      └─ Weather::Importer.call(from:, to:, data_kind:)

WeatherSyncJob
  └─ 地点・data_kindごとに最新observed_at以降の期間を決定
      └─ Weather::Importer.call(from:, to:, data_kind:)
```

`WeatherBackfillJob` と `WeatherSyncJob` は、
どちらも同じ `Weather::Importer` を利用する。

## Weather::Importer

気象データの取り込み処理を担当する。

主な責務:

- `Clients::OpenMeteoClient` を利用して対象期間のデータを取得する
- Open-Meteo固有のレスポンスをアプリで扱う形式に整える
- `WeatherSample` へ保存する
- `location_id`、`observed_at`、`data_kind` をキーに `upsert_all` 等で冪等に保存する

取得対象期間を決める責務は持たない。
分析処理も持たない。

## Clients::OpenMeteoClient

Open-Meteo APIとの通信だけを担当する。

主な責務:

- HTTPリクエスト
- Open-Meteo APIのパラメータ組み立て
- `data_kind` に応じたエンドポイント・モデルの選択
- APIレスポンスの受け取り
- Open-Meteo固有のレスポンス構造をRuby側で扱いやすい形に変換する

DBやActive Recordは知らない。

## 配置方針

`app/` 配下に `services` や `clients` などのトップレベルディレクトリを増やしすぎない。

データを扱う処理は `models` 側に寄せ、
外部APIクライアントは `lib/clients` に配置する。

```text
app/
  models/
    weather_sample.rb
    weather/
      importer.rb

  jobs/
    weather_backfill_job.rb
    weather_sync_job.rb

lib/
  clients/
    open_meteo_client.rb
```

想定クラス名:

```ruby
WeatherSample
Weather::Importer
WeatherBackfillJob
WeatherSyncJob
Clients::OpenMeteoClient
```

依存方向:

```text
WeatherBackfillJob / WeatherSyncJob
        ↓
Weather::Importer
        ├─ WeatherSample
        ↓
Clients::OpenMeteoClient
        ↓
Open-Meteo API
```

RailsのMVC構造を中心に保ちつつ、外部I/Oのみ `lib` に分離する。

## ジョブ基盤

Active Job + Solid Queue を利用する。

想定用途:

- 起動時バックフィル
- 1時間ごとの気象データ同期

Sidekiqや外部cronは初期段階では導入しない。

## 冪等性

`WeatherSample` に `(location_id, observed_at, data_kind)` の UNIQUE INDEX を設定する。

同じ地点・時刻・データ種別の気象データを何度取得しても、
重複INSERTではなくupsertできるようにする。

これにより、

- Jobの再実行
- アプリ再起動
- API取得失敗後のリトライ
- バックフィルと定期取得の期間重複

が発生しても安全に処理できる。

## 現時点で設計済みの範囲

### 1. Railsアプリ初期構成

- Rails
- PostgreSQL
- Active Job
- Solid Queue

### 2. データモデル

- `User`
- `Location`
- `WeatherSample`
- `ConditionLog`
- `DailyLog`

一次データを中心に保存し、分析用の二次データは初期段階では持たない。

### 3. 気象データ取得

- Open-Meteo
- 1時間粒度
- 初回7日バックフィル
- 以降は差分取得
- 非同期実行
- 1時間ごとの定期同期
- Job / Importer / Client の責務分離
- `(location_id, observed_at, data_kind)` UNIQUE + upsert


## ユーザーと位置情報

将来的に複数人が利用できるよう、薄い `User` モデルを持つ。

### User

```text
User
  id
```

初期段階では、名前・メールアドレス・認証情報などは持たせない。必要になった時点で追加する。

`ConditionLog` と `DailyLog` はどちらも `user_id` を持ち、ユーザーに直接紐づける。

### Location

```text
Location
  user_id
  latitude
  longitude
```

関連:

```ruby
User
  has_one :location

Location
  belongs_to :user
  has_many :weather_samples
```

気象データはユーザーそのものではなく地点に紐づける。

初期段階では、ユーザーごとに既定の地点を1つだけ使う。

- `locations.user_id`: NOT NULL、UNIQUE INDEX
- `latitude`: NOT NULL
- `longitude`: NOT NULL

### WeatherSampleの一意制約

地点ごとに即時・確定の時系列を併存させるため、

```text
UNIQUE(location_id, observed_at, data_kind)
```

とする。`observed_at` 単独、および `(location_id, observed_at)` だけではUNIQUEにしない。

### ConditionLog / DailyLog

こちらはユーザーに直接紐づける。

```ruby
User
  has_many :condition_logs
  has_many :daily_logs

ConditionLog
  belongs_to :user

DailyLog
  belongs_to :user
```

## Open-Meteoパラメータ

取得地点は `Location.latitude` / `Location.longitude` を利用する。

想定パラメータ:

```text
latitude=<Location.latitude>
longitude=<Location.longitude>

hourly=
  temperature_2m,
  relative_humidity_2m,
  precipitation,
  pressure_msl,
  weather_code

timezone=Asia/Tokyo
```

データ種別ごとのエンドポイント・モデル:

```text
realtime
  endpoint=https://api.open-meteo.com/v1/forecast
  models=jma_seamless

confirmed
  endpoint=https://archive-api.open-meteo.com/v1/archive
  models=ecmwf_ifs
```

対応:

| Open-Meteo | WeatherSample |
|---|---|
| `time` | `observed_at` |
| `pressure_msl` | `pressure_msl` |
| `temperature_2m` | `temperature` |
| `relative_humidity_2m` | `humidity` |
| `precipitation` | `precipitation` |
| `weather_code` | `weather_code` |

## フォーム設計

画面上部に3タブを置く。

```text
[ 体調 ] [ 朝の記録 ] [ 分析 ]
```

デフォルト表示は `体調`。

### ConditionLogフォーム

目的は「その瞬間の状態をすぐ記録する」こと。

項目:

- headache
- nausea
- fatigue
- appetite
- clarity

入力UI:

- 1〜10のスライダー
- 前回のConditionLogの値を初期値として引き継ぐ
- スライダー操作中だけ現在値を表示する
- `recorded_at` は現在時刻を基本値とする
- 保存時には常に新規レコードを作成する
- フォームを開いただけでは記録しない

### DailyLogフォーム

朝に1回入力する。

項目:

- wakeup_freshness
- sleep_minutes
- steps
- drank_alcohol
- screen_minutes

入力UI:

#### wakeup_freshness

- 1〜10のスライダー
- 初期値は5
- 前日値は引き継がない
- 操作中だけ現在値を表示する

#### sleep_minutes / screen_minutes

フォーム上は「時間」「分」の2入力。

```text
睡眠時間    [ 6 ] 時間 [ 30 ] 分
画面時間    [ 8 ] 時間 [ 15 ] 分
```

DBには総分数で保存する。

#### steps

単純な数値入力。

#### drank_alcohol

Yes / No の二択。

### DailyLogの更新ルール

ユーザーごとに1日1レコード。同じ日付の入力が既にある場合はUPDATEする。

## 分析画面

初期構成:

```text
分析
  ├─ 時系列
  ├─ 最近の記録
  └─ 傾向
```

### 時系列

気象データと体調ログを同じ時間軸で可視化する。

主に見るもの:

- pressure_msl
- temperature
- humidity
- ConditionLog各項目

### 最近の記録

直近のConditionLogについて、その時点より前の気圧変化を確認する。

### 傾向

一定条件のときに症状がどの程度起きているかを集計する。
割合だけでなく必ず母数も表示する。

例:

```text
通常:
fatigue >= 7
32 / 100 = 32%

6時間で3hPa以上低下:
fatigue >= 7
12 / 16 = 75%
```

## 分析指標

ConditionLogの `recorded_at` に対し、直前の1時間WeatherSampleを基準時点として使う。

分析対象に応じて `data_kind` を1つ選び、その種別の時系列だけで指標を算出する。`realtime` と `confirmed` を同じ計算に混在させない。

例:

```text
ConditionLog: 14:23
基準WeatherSample: 14:00
```

未来の気象データは使わない。

### 気圧変化量

基準時点の気圧を `P(t)` とする。

```text
Δ3h  = P(t) - P(t - 3h)
Δ6h  = P(t) - P(t - 6h)
Δ12h = P(t) - P(t - 12h)
Δ24h = P(t) - P(t - 24h)
```

負値は気圧低下、正値は気圧上昇を表す。

### 気圧レンジ

```text
直近6hレンジ  = max(pressure) - min(pressure)
直近24hレンジ = max(pressure) - min(pressure)
```

### 保存方針

これらの分析指標は初期段階ではDBに保存しない。`WeatherSample` から都度計算する。

将来必要になった場合のみ、キャッシュ・集計テーブル・materialized view等を検討する。

## ラグ分析

ConditionLogの記録時刻から、N時間前の気圧状態との相関を見る。

例:

```text
ConditionLog at 14:23
基準WeatherSample = 14:00

lag 0h
  → 14:00時点の Δ3h / Δ6h / Δ12h / Δ24h

lag 3h
  → 11:00時点の各指標

lag 6h
  → 08:00時点の各指標

lag 12h
  → 02:00時点の各指標
```

ConditionLog自体の記録間隔が不規則でも、気象データが1時間粒度で連続していれば分析可能。

初期候補:

- lag 0h
- lag 3h
- lag 6h
- lag 12h

必要に応じて後から追加する。

## 分析方針

単純な相関係数だけではなく、複数の観点から見る。

- 相関
- 閾値
- 時間差（lag）
- 複合条件
- 気圧の上昇 / 下降
- 気圧の変動幅
- ベースライン比較

特定の「気圧低下が悪い」という仮説を固定せず、上昇・下降の両方を対象にする。

### ベースライン

初期段階ではConditionLog全体の分布を基準とする。

データ量が増えた場合は、朝・昼・夜など時間帯別ベースラインも検討する。

## 欠損データ

分析時に補間するのではなく、可能な限りOpen-Meteoから再取得して元データを揃える。

### WeatherSyncJob

定期同期時に、

1. `data_kind` ごとに最新WeatherSample以降のデータを取得する
2. `data_kind` ごとに直近一定期間に欠損時刻がないか確認する
3. 欠損があれば対象期間を再取得する

という方針にする。

Importer側は期間判定を行わず、指定された期間を取得・upsertするだけとする。

## 初期版の全体構成

```text
User
 ├─ has_one Location
 │     └─ has_many WeatherSamples
 ├─ has_many ConditionLogs
 └─ has_many DailyLogs
```

```text
Open-Meteo
    ↓
Clients::OpenMeteoClient
    ↓
Weather::Importer
    ↓
WeatherSample
```

```text
WeatherBackfillJob / WeatherSyncJob
    ↓
取得期間を決定
    ↓
Weather::Importer
```

```text
UI
  ├─ 体調
  │    └─ ConditionLog
  ├─ 朝の記録
  │    └─ DailyLog
  └─ 分析
       ├─ 時系列
       ├─ 最近の記録
       └─ 傾向
```

## 現時点で設計済みの範囲

### 1. アプリ基盤
- Rails
- PostgreSQL
- Active Job
- Solid Queue

### 2. データモデル
- User
- Location
- WeatherSample
- ConditionLog
- DailyLog

### 3. 気象取得
- Open-Meteo Forecast API（JMA）による即時データ
- Open-Meteo Historical Weather API（ECMWF IFS）による確定データ
- 1時間粒度
- 初回7日バックフィル
- 差分取得
- 欠損再取得
- 非同期実行
- 1時間ごとの定期同期
- Job / Importer / Client の責務分離
- `(location_id, observed_at, data_kind)` UNIQUE + upsert
- 即時データ（JMA）と確定データ（履歴API）の併存

### 4. 入力UI
- ConditionLogフォーム
- DailyLogフォーム
- スライダーUI
- 3タブ構成

### 5. 分析
- 時系列
- Δ3h / Δ6h / Δ12h / Δ24h
- 6h / 24hレンジ
- lag 0h / 3h / 6h / 12h
- 相関
- 閾値
- ベースライン比較
- 複合条件
- 上昇・下降の双方を分析

## 実装時に決めればよいこと

- decimalのprecision / scale
- migrationの細部
- Model validationの細部
- Open-Meteo HTTPクライアントの具体実装
- Importer / Clientの具体的メソッドシグネチャ
- 起動時BackfillJob enqueueの方法
- グラフライブラリ
- 分析期間の初期値（7日 / 30日 / 90日など）
- 症状の閾値初期値
