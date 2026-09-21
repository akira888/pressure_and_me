class CreateWeatherSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :weather_samples do |t|
      t.references :location, null: false, foreign_key: true, index: false
      t.datetime :observed_at, null: false
      t.integer :data_kind, null: false
      t.decimal :pressure_msl, precision: 12, scale: 6
      t.decimal :temperature, precision: 12, scale: 6
      t.integer :humidity
      t.decimal :precipitation, precision: 12, scale: 6
      t.integer :weather_code
      t.timestamps

      t.index [ :location_id, :observed_at, :data_kind ], unique: true
      t.check_constraint "data_kind IN (0, 1)", name: "weather_samples_data_kind_valid"
    end
  end
end
