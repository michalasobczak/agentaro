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

ActiveRecord::Schema[8.1].define(version: 2026_11_19_120100) do
  create_table "audit_events", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "request_id", null: false
    t.integer "user_id"
    t.string "username"
    t.integer "session_id"
    t.string "remote_addr"
    t.string "forwarded_for"
    t.string "user_agent"
    t.string "http_method", null: false
    t.string "host"
    t.string "path", null: false
    t.text "query"
    t.text "body"
    t.integer "status"
    t.float "duration_ms"
    t.string "prev_hash", null: false
    t.string "row_hash", null: false
    t.index ["occurred_at"], name: "index_audit_events_on_occurred_at"
    t.index ["request_id"], name: "index_audit_events_on_request_id"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
  end

  create_table "chain_anchors", force: :cascade do |t|
    t.string "chain", null: false
    t.string "anchor_hash", null: false
    t.datetime "pruned_before"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chain"], name: "index_chain_anchors_on_chain", unique: true
  end

  create_table "data_changes", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "request_id"
    t.string "actor", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.string "action", null: false
    t.text "changeset", null: false
    t.string "prev_hash", null: false
    t.string "row_hash", null: false
    t.index ["occurred_at"], name: "index_data_changes_on_occurred_at"
    t.index ["record_type", "record_id"], name: "index_data_changes_on_record_type_and_record_id"
    t.index ["request_id"], name: "index_data_changes_on_request_id"
  end
end
