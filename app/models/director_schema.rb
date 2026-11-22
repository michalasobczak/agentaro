# Spec 044, G2: the shapes of the director's answers, as JSON schemas. A local server (Ollama, LM Studio,
# OpenAI-compatible) is held to them; Agentaro still checks every answer and action as before (R3).
module DirectorSchema
  # Every field any action uses, all optional but "type": a grammar-held model may write only declared fields
  # (found by the acceptance run: with "type" alone it invented "add_item_add_epic" and could add no title).
  ACTION_TYPES = %w[add_item update_item add_space update_space cancel_item remember forget approve_facts reject_facts
                    reprioritize add_recurring update_recurring pause_recurring resume_recurring cancel_recurring
                    answer_decision approve_plan set_autonomy stop_process set_reply_length set_style set_conversation
                    set_tempo reassign_step retry_step pause_epic resume_epic].freeze
  TEXT = { type: [ "string", "null" ] }.freeze
  NUMBER = { type: [ "integer", "null" ] }.freeze
  ACTION = { type: "object", properties: {
    type: { type: "string", enum: ACTION_TYPES },
    id: NUMBER, space: { type: [ "integer", "string", "null" ] }, title: TEXT, description: TEXT, starts_at: TEXT, due_on: TEXT,
    priority: TEXT, kind: TEXT, name: TEXT, goal: TEXT, subject: TEXT, statement: TEXT, ids: { type: "array", items: { type: "integer" } },
    level: NUMBER, step: NUMBER, agent: NUMBER, attempt: NUMBER, run: NUMBER, pid: NUMBER, answer: TEXT,
    schedule: { type: [ "object", "null" ], properties: { kind: TEXT, time: TEXT, weekdays: { type: "array", items: { type: "integer" } },
                                                          day: NUMBER, every_hours: NUMBER } },
    starts_on: TEXT, ends_on: TEXT, report: TEXT
  }, required: [ "type" ] }.freeze

  CHAT = { type: "object", properties: { reply: { type: "string" }, actions: { type: "array", items: ACTION } },
           required: %w[reply actions] }.freeze

  STEP = { type: "object", properties: { title: { type: "string" }, description: { type: "string" }, agent: { type: "integer" },
                                         minutes: { type: "integer" } }, required: %w[title description agent] }.freeze

  PLAN = { type: "object", properties: { summary: { type: "string" }, steps: { type: "array", items: STEP },
                                         assumptions: { type: "array", items: { type: "string" } }, blocked: { type: "string" } },
           required: %w[summary steps assumptions] }.freeze

  REVIEW = { type: "object", properties: {
    decision: { type: "string", enum: %w[retry change replan stop ask] }, reason: { type: "string" },
    minutes: { type: [ "integer", "null" ] }, at: { type: [ "string", "null" ] }, instructions: { type: "string" },
    steps: { type: "array", items: STEP }, question: { type: "string" }, options: { type: "array", items: { type: "string" } },
    recommended: { type: "string" }
  }, required: %w[decision reason] }.freeze

  SUMMARY = { type: "object", properties: { summary: { type: "string" } }, required: [ "summary" ] }.freeze # spec 045
end
