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

ActiveRecord::Schema[8.1].define(version: 2026_11_21_170000) do
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
    t.string "effort"
    t.datetime "model_checked_at"
    t.boolean "model_check_ok"
    t.text "model_check_output"
    t.integer "max_parallel_tasks", default: 6, null: false
    t.index ["executor_id"], name: "index_agents_on_executor_id"
    t.index ["kind", "user_id", "name"], name: "index_agents_on_kind_and_user_id_and_name"
    t.index ["user_id"], name: "index_agents_on_user_id"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "author", null: false
    t.text "content", null: false
    t.text "actions_summary"
    t.integer "task_run_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.boolean "spoken", default: false, null: false
    t.integer "reply_to_id"
    t.index ["task_run_id"], name: "index_chat_messages_on_task_run_id"
    t.index ["user_id", "archived_at"], name: "index_chat_messages_on_user_id_and_archived_at"
    t.index ["user_id"], name: "index_chat_messages_on_user_id"
  end

  create_table "epic_steps", force: :cascade do |t|
    t.integer "work_item_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "agent_id"
    t.string "state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_epic_steps_on_agent_id"
    t.index ["work_item_id", "position"], name: "index_epic_steps_on_work_item_id_and_position", unique: true
    t.index ["work_item_id"], name: "index_epic_steps_on_work_item_id"
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
    t.json "models"
    t.datetime "models_listed_at"
    t.text "models_note"
    t.text "extra_models"
    t.string "effort"
    t.datetime "model_checked_at"
    t.boolean "model_check_ok"
    t.text "model_check_output"
    t.index ["name"], name: "index_executors_on_name", unique: true
  end

  create_table "memory_blocks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "scope_type", null: false
    t.integer "scope_id"
    t.text "content", default: "", null: false
    t.integer "version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "scope_type", "scope_id"], name: "index_memory_blocks_on_user_id_and_scope_type_and_scope_id", unique: true
    t.index ["user_id"], name: "index_memory_blocks_on_user_id"
  end

  create_table "memory_episodes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "kind", null: false
    t.string "source_type"
    t.integer "source_id"
    t.text "excerpt", null: false
    t.datetime "occurred_at", null: false
    t.datetime "processed_at"
    t.integer "attempts", default: 0, null: false
    t.datetime "next_attempt_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_id"], name: "index_memory_episodes_on_source_type_and_source_id"
    t.index ["user_id", "processed_at"], name: "index_memory_episodes_on_user_id_and_processed_at"
    t.index ["user_id"], name: "index_memory_episodes_on_user_id"
  end

  create_table "memory_fact_sources", force: :cascade do |t|
    t.integer "memory_fact_id", null: false
    t.integer "memory_episode_id", null: false
    t.index ["memory_episode_id"], name: "index_memory_fact_sources_on_memory_episode_id"
    t.index ["memory_fact_id", "memory_episode_id"], name: "idx_on_memory_fact_id_memory_episode_id_561796dd44", unique: true
    t.index ["memory_fact_id"], name: "index_memory_fact_sources_on_memory_fact_id"
  end

  create_table "memory_facts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "subject_type", null: false
    t.integer "subject_id"
    t.string "kind", null: false
    t.string "statement", null: false
    t.string "status", default: "active", null: false
    t.string "origin", default: "extracted", null: false
    t.float "confidence", default: 0.7, null: false
    t.datetime "valid_from", null: false
    t.datetime "invalid_at"
    t.integer "superseded_by_id"
    t.integer "supersedes_id"
    t.boolean "pinned", default: false, null: false
    t.datetime "last_used_at"
    t.integer "use_count", default: 0, null: false
    t.binary "embedding"
    t.string "embedding_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["superseded_by_id"], name: "index_memory_facts_on_superseded_by_id"
    t.index ["supersedes_id"], name: "index_memory_facts_on_supersedes_id"
    t.index ["user_id", "status", "subject_type", "subject_id"], name: "idx_on_user_id_status_subject_type_subject_id_3196625777"
    t.index ["user_id"], name: "index_memory_facts_on_user_id"
  end

  create_table "model_call_parts", force: :cascade do |t|
    t.integer "model_call_id", null: false
    t.integer "trace_part_id", null: false
    t.integer "position", null: false
    t.integer "section", null: false
    t.string "kind", null: false
    t.index ["model_call_id", "position"], name: "index_model_call_parts_on_model_call_id_and_position", unique: true
    t.index ["model_call_id"], name: "index_model_call_parts_on_model_call_id"
    t.index ["trace_part_id"], name: "index_model_call_parts_on_trace_part_id"
  end

  create_table "model_calls", force: :cascade do |t|
    t.integer "task_run_id", null: false
    t.integer "user_id"
    t.integer "position", null: false
    t.string "pass", null: false
    t.string "layout", default: "agent", null: false
    t.integer "agent_id"
    t.string "agent_name"
    t.string "preset"
    t.string "model"
    t.string "effort"
    t.string "state"
    t.datetime "started_at"
    t.integer "duration_ms"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.float "cost_usd"
    t.integer "turns"
    t.string "joiner", default: "\n\n", null: false
    t.integer "output_part_id"
    t.text "error"
    t.boolean "redacted", default: false, null: false
    t.binary "events"
    t.string "events_format"
    t.integer "events_count", default: 0, null: false
    t.boolean "events_cut", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["output_part_id"], name: "index_model_calls_on_output_part_id"
    t.index ["task_run_id", "position"], name: "index_model_calls_on_task_run_id_and_position", unique: true
    t.index ["task_run_id"], name: "index_model_calls_on_task_run_id"
    t.index ["user_id", "created_at"], name: "index_model_calls_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_model_calls_on_user_id"
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

  create_table "recurring_orders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "space_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "kind", default: "weekly", null: false
    t.string "at_time", default: "08:00", null: false
    t.string "weekdays"
    t.integer "month_day"
    t.integer "every_hours"
    t.date "starts_on", null: false
    t.date "ends_on"
    t.string "state", default: "active", null: false
    t.string "report", default: "always", null: false
    t.json "last_plan"
    t.text "last_plan_summary"
    t.datetime "next_at"
    t.datetime "last_occurrence_at"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space_id"], name: "index_recurring_orders_on_space_id"
    t.index ["state", "next_at"], name: "index_recurring_orders_on_state_and_next_at"
    t.index ["user_id"], name: "index_recurring_orders_on_user_id"
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

  create_table "spaces", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.text "goal"
    t.text "description"
    t.string "state", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "project", null: false
    t.string "working_dir"
    t.integer "autonomy_level"
    t.index ["user_id", "name"], name: "index_spaces_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_spaces_on_user_id"
  end

  create_table "step_decisions", force: :cascade do |t|
    t.integer "work_item_id", null: false
    t.integer "epic_step_id"
    t.integer "task_run_id"
    t.string "status", default: "pending", null: false
    t.string "answered_by"
    t.text "question"
    t.json "options"
    t.text "recommended"
    t.text "why"
    t.boolean "important", default: false, null: false
    t.boolean "always_ask", default: false, null: false
    t.text "answer"
    t.text "correction"
    t.datetime "corrected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["epic_step_id"], name: "index_step_decisions_on_epic_step_id"
    t.index ["task_run_id"], name: "index_step_decisions_on_task_run_id"
    t.index ["work_item_id", "status"], name: "index_step_decisions_on_work_item_id_and_status"
    t.index ["work_item_id"], name: "index_step_decisions_on_work_item_id"
  end

  create_table "task_exceptions", force: :cascade do |t|
    t.integer "task_id", null: false
    t.datetime "occurs_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "occurs_at"], name: "index_task_exceptions_on_task_id_and_occurs_at", unique: true
    t.index ["task_id"], name: "index_task_exceptions_on_task_id"
  end

  create_table "task_runs", force: :cascade do |t|
    t.integer "task_id"
    t.datetime "occurrence_start", null: false
    t.string "trigger", null: false
    t.string "state", default: "queued", null: false
    t.string "requested_by"
    t.string "agent_name"
    t.string "executor_name"
    t.string "preset"
    t.string "model"
    t.text "prompt"
    t.text "output"
    t.text "error"
    t.integer "exit_status"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "purpose", default: "step", null: false
    t.integer "user_id"
    t.integer "work_item_id"
    t.integer "agent_id"
    t.integer "epic_step_id"
    t.string "failure_kind"
    t.datetime "retry_at"
    t.integer "attempt", default: 1, null: false
    t.integer "pid"
    t.index ["agent_id"], name: "index_task_runs_on_agent_id"
    t.index ["epic_step_id"], name: "index_task_runs_on_epic_step_id"
    t.index ["state", "created_at"], name: "index_task_runs_on_state_and_created_at"
    t.index ["state", "retry_at"], name: "index_task_runs_on_state_and_retry_at"
    t.index ["task_id", "occurrence_start"], name: "index_task_runs_one_scheduled_per_occurrence", unique: true, where: "\"trigger\" = 'scheduled'"
    t.index ["task_id"], name: "index_task_runs_on_task_id"
    t.index ["user_id"], name: "index_task_runs_on_user_id"
    t.index ["work_item_id"], name: "index_task_runs_on_work_item_id"
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
    t.datetime "agent_assigned_at"
    t.integer "work_item_id"
    t.index ["agent_id"], name: "index_tasks_on_agent_id"
    t.index ["calendar", "starts_at"], name: "index_tasks_on_calendar_and_starts_at"
    t.index ["user_id", "starts_at"], name: "index_tasks_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_tasks_on_user_id"
    t.index ["work_item_id"], name: "index_tasks_on_work_item_id"
  end

  create_table "team_roles", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "agent_id", null: false
    t.string "role", null: false
    t.string "role_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_team_roles_on_agent_id"
    t.index ["user_id", "role", "agent_id"], name: "index_team_roles_unique", unique: true
    t.index ["user_id"], name: "index_team_roles_on_user_id"
  end

  create_table "trace_parts", force: :cascade do |t|
    t.string "digest", null: false
    t.text "content", null: false
    t.integer "bytes", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["digest"], name: "index_trace_parts_on_digest", unique: true
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
    t.string "chat_language", default: "auto", null: false
    t.boolean "verifier_active", default: false, null: false
    t.decimal "speech_speed", precision: 3, scale: 2, default: "1.5", null: false
    t.string "theme", default: "auto", null: false
    t.string "chat_background", default: "solid", null: false
    t.boolean "auto_retry", default: true, null: false
    t.integer "autonomy_level", default: 2, null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "work_items", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "starts_at"
    t.date "due_on"
    t.string "priority", default: "normal", null: false
    t.integer "position", default: 0, null: false
    t.string "state", default: "new", null: false
    t.text "plan_summary"
    t.text "blocked_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "space_id", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "active_step_from", default: 1, null: false
    t.datetime "block_dismissed_at"
    t.boolean "awaiting_approval", default: false, null: false
    t.integer "clarifications", default: 0, null: false
    t.integer "recurring_order_id"
    t.index ["recurring_order_id"], name: "index_work_items_on_recurring_order_id"
    t.index ["space_id"], name: "index_work_items_on_space_id"
    t.index ["user_id", "state"], name: "index_work_items_on_user_id_and_state"
    t.index ["user_id"], name: "index_work_items_on_user_id"
  end

  add_foreign_key "agents", "executors"
  add_foreign_key "agents", "users"
  add_foreign_key "chat_messages", "task_runs"
  add_foreign_key "chat_messages", "users"
  add_foreign_key "epic_steps", "agents"
  add_foreign_key "epic_steps", "work_items"
  add_foreign_key "memory_blocks", "users"
  add_foreign_key "memory_episodes", "users"
  add_foreign_key "memory_fact_sources", "memory_episodes"
  add_foreign_key "memory_fact_sources", "memory_facts"
  add_foreign_key "memory_facts", "memory_facts", column: "superseded_by_id"
  add_foreign_key "memory_facts", "memory_facts", column: "supersedes_id"
  add_foreign_key "memory_facts", "users"
  add_foreign_key "model_call_parts", "model_calls"
  add_foreign_key "model_call_parts", "trace_parts"
  add_foreign_key "model_calls", "task_runs"
  add_foreign_key "model_calls", "trace_parts", column: "output_part_id"
  add_foreign_key "model_calls", "users"
  add_foreign_key "password_links", "users"
  add_foreign_key "password_links", "users", column: "created_by_id"
  add_foreign_key "recurring_orders", "spaces"
  add_foreign_key "recurring_orders", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "spaces", "users"
  add_foreign_key "step_decisions", "epic_steps"
  add_foreign_key "step_decisions", "task_runs"
  add_foreign_key "step_decisions", "work_items"
  add_foreign_key "task_exceptions", "tasks"
  add_foreign_key "task_runs", "agents"
  add_foreign_key "task_runs", "epic_steps"
  add_foreign_key "task_runs", "tasks"
  add_foreign_key "task_runs", "users"
  add_foreign_key "task_runs", "work_items"
  add_foreign_key "tasks", "agents"
  add_foreign_key "tasks", "users"
  add_foreign_key "tasks", "work_items"
  add_foreign_key "team_roles", "agents"
  add_foreign_key "team_roles", "users"
  add_foreign_key "work_items", "recurring_orders"
  add_foreign_key "work_items", "spaces"
  add_foreign_key "work_items", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "memory_facts_fts", "fts5", ["statement", "tokenize='unicode61 remove_diacritics 2'"]
end
