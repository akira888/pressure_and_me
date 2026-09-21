# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_21_080004) do
  create_table "condition_logs", force: :cascade do |t|
    t.integer "appetite", null: false
    t.integer "clarity", null: false
    t.datetime "created_at", null: false
    t.integer "fatigue", null: false
    t.integer "headache", null: false
    t.integer "nausea", null: false
    t.datetime "recorded_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "recorded_at"], name: "index_condition_logs_on_user_id_and_recorded_at"
    t.check_constraint "appetite BETWEEN 1 AND 10 AND appetite = CAST(appetite AS BIGINT)", name: "condition_logs_appetite_valid"
    t.check_constraint "clarity BETWEEN 1 AND 10 AND clarity = CAST(clarity AS BIGINT)", name: "condition_logs_clarity_valid"
    t.check_constraint "fatigue BETWEEN 1 AND 10 AND fatigue = CAST(fatigue AS BIGINT)", name: "condition_logs_fatigue_valid"
    t.check_constraint "headache BETWEEN 1 AND 10 AND headache = CAST(headache AS BIGINT)", name: "condition_logs_headache_valid"
    t.check_constraint "nausea BETWEEN 1 AND 10 AND nausea = CAST(nausea AS BIGINT)", name: "condition_logs_nausea_valid"
  end

  create_table "daily_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.boolean "drank_alcohol", null: false
    t.integer "screen_minutes", null: false
    t.integer "sleep_minutes", null: false
    t.integer "steps", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "wakeup_freshness", null: false
    t.index ["user_id", "date"], name: "index_daily_logs_on_user_id_and_date", unique: true
    t.check_constraint "screen_minutes >= 0 AND screen_minutes = CAST(screen_minutes AS BIGINT)", name: "daily_logs_screen_minutes_valid"
    t.check_constraint "sleep_minutes >= 0 AND sleep_minutes = CAST(sleep_minutes AS BIGINT)", name: "daily_logs_sleep_minutes_valid"
    t.check_constraint "steps >= 0 AND steps = CAST(steps AS BIGINT)", name: "daily_logs_steps_valid"
    t.check_constraint "wakeup_freshness BETWEEN 1 AND 10 AND wakeup_freshness = CAST(wakeup_freshness AS BIGINT)", name: "daily_logs_wakeup_freshness_valid"
  end

  create_table "locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_locations_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "weather_samples", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "data_kind", null: false
    t.integer "humidity"
    t.integer "location_id", null: false
    t.datetime "observed_at", null: false
    t.decimal "precipitation", precision: 12, scale: 6
    t.decimal "pressure_msl", precision: 12, scale: 6
    t.decimal "temperature", precision: 12, scale: 6
    t.datetime "updated_at", null: false
    t.integer "weather_code"
    t.index ["location_id", "observed_at", "data_kind"], name: "idx_on_location_id_observed_at_data_kind_8b578589af", unique: true
    t.check_constraint "data_kind IN (0, 1)", name: "weather_samples_data_kind_valid"
  end

  add_foreign_key "condition_logs", "users"
  add_foreign_key "daily_logs", "users"
  add_foreign_key "locations", "users"
  add_foreign_key "weather_samples", "locations"
end
