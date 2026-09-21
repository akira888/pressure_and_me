class CreateConditionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :condition_logs do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.datetime :recorded_at, null: false
      t.integer :headache, null: false
      t.integer :nausea, null: false
      t.integer :fatigue, null: false
      t.integer :appetite, null: false
      t.integer :clarity, null: false
      t.timestamps

      t.index [ :user_id, :recorded_at ]
      %w[headache nausea fatigue appetite clarity].each do |score|
        t.check_constraint "#{score} BETWEEN 1 AND 10 AND #{score} = CAST(#{score} AS BIGINT)",
          name: "condition_logs_#{score}_valid"
      end
    end
  end
end
