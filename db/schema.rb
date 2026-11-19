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

ActiveRecord::Schema[8.1].define(version: 2026_11_19_220000) do
  create_table "agents", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "kind", default: "private", null: false
    t.string "name", null: false
    t.string "description"
    t.text "master_prompt", null: false
    t.integer "executor_id", null: false
    t.string "model"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["executor_id"], name: "index_agents_on_executor_id"
    t.index ["kind", "user_id", "name"], name: "index_agents_on_kind_and_user_id_and_name"
    t.index ["user_id"], name: "index_agents_on_user_id"
  end

  create_table "executors", force: :cascade do |t|
    t.string "name", null: false
    t.string "preset", null: false
    t.boolean "enabled", default: true, null: false
    t.string "base_url"
    t.string "default_model"
    t.text "notes"
    t.datetime "last_checked_at"
    t.boolean "last_check_ok"
    t.text "last_check_output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_executors_on_name", unique: true
  end

  create_table "password_links", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "created_by_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_password_links_on_created_by_id"
    t.index ["token_digest"], name: "index_password_links_on_token_digest", unique: true
    t.index ["user_id"], name: "index_password_links_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.boolean "otp_verified", default: false, null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sign_in_throttles", force: :cascade do |t|
    t.string "username", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_sign_in_throttles_on_username", unique: true
  end

  create_table "task_exceptions", force: :cascade do |t|
    t.integer "task_id", null: false
    t.datetime "occurs_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "occurs_at"], name: "index_task_exceptions_on_task_id_and_occurs_at", unique: true
    t.index ["task_id"], name: "index_task_exceptions_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "calendar", default: "private", null: false
    t.string "title", null: false
    t.string "location"
    t.text "description"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.boolean "all_day", default: false, null: false
    t.string "repeat", default: "none", null: false
    t.integer "repeat_interval", default: 1, null: false
    t.string "repeat_weekdays"
    t.date "repeat_until"
    t.integer "repeat_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "agent_id"
    t.index ["agent_id"], name: "index_tasks_on_agent_id"
    t.index ["calendar", "starts_at"], name: "index_tasks_on_calendar_and_starts_at"
    t.index ["user_id", "starts_at"], name: "index_tasks_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "password_digest"
    t.string "role", default: "user", null: false
    t.string "otp_secret"
    t.boolean "otp_required", default: false, null: false
    t.datetime "otp_last_used_at"
    t.boolean "active", default: true, null: false
    t.datetime "password_changed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "agents", "executors"
  add_foreign_key "agents", "users"
  add_foreign_key "password_links", "users"
  add_foreign_key "password_links", "users", column: "created_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "task_exceptions", "tasks"
  add_foreign_key "tasks", "agents"
  add_foreign_key "tasks", "users"
end
