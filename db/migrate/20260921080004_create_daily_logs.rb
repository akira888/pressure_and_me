class CreateDailyLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_logs do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.integer :wakeup_freshness, null: false
      t.integer :sleep_minutes, null: false
      t.integer :steps, null: false
      t.boolean :drank_alcohol, null: false
      t.integer :screen_minutes, null: false
      t.timestamps

      t.index [ :user_id, :date ], unique: true
      t.check_constraint "wakeup_freshness BETWEEN 1 AND 10 AND wakeup_freshness = CAST(wakeup_freshness AS BIGINT)",
        name: "daily_logs_wakeup_freshness_valid"
      %w[sleep_minutes steps screen_minutes].each do |count|
        t.check_constraint "#{count} >= 0 AND #{count} = CAST(#{count} AS BIGINT)",
          name: "daily_logs_#{count}_valid"
      end
    end
  end
end
