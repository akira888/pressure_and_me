# Pressure and Me

気象変化と自分の体調を記録・分析するRailsアプリです。
仕様の正本は [設計メモ](.codex/pressure_condition_app_design.md)、作業状況は [TODO](.codex/TODO.md) を参照してください。

## 開発環境

- Ruby 4.0.1（`.ruby-version`）
- Rails 8.1.3.1（依存バージョンは `Gemfile.lock`）
- SQLite 3
- Active Job + Solid Queue
- Importmap + Turbo + Stimulus（Node.js不要）

Rails 8.1のJSON呼び出しと互換性を保つため、`json` gemは2系に固定しています。

## 初回セットアップ

```sh
bundle install
bin/rails db:prepare
bin/dev
```

または `bin/setup` で依存インストール、DB準備、サーバー起動をまとめて実行できます。
準備だけなら `bin/setup --skip-server` を使います。

[http://localhost:3000](http://localhost:3000) にアクセスします。
`bin/rails db:seed` で初期ユーザー（id: 1）を作成すると、コンソールでUUIDを確認できます。

```sh
bin/rails runner 'puts User.find(1).uuid'
```

表示されたUUIDを使って `http://localhost:3000/u/<UUID>` を開くと、体調入力画面を起点に
「体調」「朝の記録」「分析」の3タブを利用できます。ログイン画面は設けず、URLのUUIDで
ユーザーを識別します。既定地点は設定UIを設けず、必要に応じてRailsコンソールから登録します。
ヘルスチェックは `/up` です。
`bin/dev` はPuma内でSolid Queueも起動するため、ジョブ用の別ターミナルは不要です。
Ctrl-Cで停止できます。

Webとジョブを分けて起動する場合は、各ターミナルで次を実行します。

```sh
# ターミナル1
bin/rails server

# ターミナル2
bin/jobs
```

`bin/dev` と `bin/jobs` の同時起動は不要です。
地点登録時の初回取得、毎時同期、Solid Queue再開時の補完が非同期で実行されます。

## DBと日時

- アプリの日時・日付境界は `Asia/Tokyo`。DBの日時保存はRails標準のUTCです。
- 開発用DBは `storage/development.sqlite3`、ジョブ用DBは `storage/development_queue.sqlite3` です。
- テストは `storage/test.sqlite3` とActive Jobのテストアダプターを使います。
- 全環境のSQLiteに `journal_mode: wal`、ロック待ち時間 `timeout: 5000`（ミリ秒）を設定しています。
- DBファイルと `config/master.key` はGit管理対象外です。

本番では `storage/` を永続ローカルディスクまたは永続ボリュームにマウントし、
`RAILS_ENV=production bin/rails db:prepare` でprimary・queue・cache・cableのDBを準備します。
`RAILS_MASTER_KEY` には安全に保管した `config/master.key` の値を設定してください。
ジョブは `RAILS_ENV=production bin/jobs` を別プロセスで動かすか、
`SOLID_QUEUE_IN_PUMA=true` を設定してWebと一緒に起動します。
デプロイ先の設定はまだ行っていません。

## 検証

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop
```

Rails標準のCI設定も含めています。`bin/ci` は上記に加えて依存関係などの
セキュリティ検査を実行するため、ネットワーク接続が必要です。

## 気象データの手動取り込み

Phase 3では、Railsコンソールから指定期間を取得・保存できます。
先に既定地点を登録した状態で、`bin/rails console` から実行します。

```ruby
location = Location.first!
from = Time.current.beginning_of_hour - 24.hours
to = Time.current

Weather::Importer.call(location: location, from: from, to: to, data_kind: :realtime)
Weather::Importer.call(location: location, from: from, to: to, data_kind: :confirmed)
```

返り値は期間内の利用可能なサンプル数です。範囲は両端を含みます。
同じ地点・時刻・種別の再取得は更新になり、別の系列は変更しません。
全項目が欠けた時間は保存せず、一部の欠損はNULLとして保存します。
通信・レスポンスのエラーは例外で通知し、その取得分は保存しません。
自動同期はPhase 4で追加した`WeatherSyncJob`が担当します。

取得モデルなどの仕様とエラー種別は[設計メモ](.codex/pressure_condition_app_design.md)を参照してください。
API関連のテストは固定レスポンスを使うため、ネットワーク接続なしで実行できます。

```sh
PARALLEL_WORKERS=1 bin/rails test test/lib/clients/open_meteo_client_test.rb test/models/weather/importer_test.rb
```

## 非同期同期

Phase 4で`WeatherBackfillJob`と`WeatherSyncJob`を追加しました。
どちらも`weather`キューで実行されます。初回取得は地点登録の確定後に自動で予約され、
その後はSolid Queueのdevelopment/production設定で`WeatherSyncJob`が毎時実行されます。
`bin/dev`または`bin/jobs`によるSolid Queueの開始・再開時にも同期を予約します。

```ruby
WeatherBackfillJob.perform_later(location_id: location.id)
WeatherSyncJob.perform_later
```

上のコマンドは手動で再取得したい場合に使います。初回取得は地点の登録時刻を基準に
直近24時間の分析に必要な毎正時のデータを取得します。例えば10:37の登録では前日の10:00からです。
実行が遅れても取得開始点を変えず、実行時刻までを補います。
Locationを指定しない手動バックフィルは全地点が対象です。

通常同期は系列ごとの最新時刻を起点に、直近24時間の欠損も再取得します。
停止していた場合は24時間より長い空白も、APIが提供する範囲で補完します。
取得済みデータがない系列は登録時の初回取得範囲から補います。
サイトへのアクセス・リロード・地点の更新では、初回取得を予約しません。
ジョブを再実行しても、地点・時刻・系列の一意キーで重複せず更新されます。
