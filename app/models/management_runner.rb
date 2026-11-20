# Spec 011, corrected by spec 012: the director runs like any agent (spec 010) but answers in JSON.
# Agents propose, Agentaro applies (R1): every answer is parsed, checked against the user's own list, team
# and the rules, and only then applied. An invalid answer is retried once with the errors.
#
# Purposes: "chat" (the director answers the user, spec 011 G1) and "director" (the director plans a due item
# for its members, spec 012 G2). "manager" and "review" exist only in runs from before spec 012.
class ManagementRunner
  MAX_STEPS = 10
  HORIZON = 14.days
  MAX_ACTIONS = 20
  LEGACY = %w[manager review].freeze
  HISTORY = 30 # chat messages the director sees

  Invalid = Class.new(StandardError)

  # --- Starting management runs ------------------------------------------------------------------

  def self.queue!(user:, purpose:, work_item: nil, agent:)
    run = TaskRun.create!(user: user, work_item: work_item, agent: agent, purpose: purpose, trigger: "scheduled",
                          occurrence_start: Time.current, state: "queued")
    Agentaro::TaskScheduler.enqueue(run.id)
    run
  end

  # G1: a user wrote to the director. One chat run per user at a time (R3).
  def self.chat!(user)
    director = user.director_role&.agent
    return nil unless director
    return nil if TaskRun.where(user: user, purpose: "chat", state: %w[queued running]).exists?

    queue!(user: user, purpose: "chat", agent: director)
  end

  # Items whose time has come go to the director to be planned (spec 012, G2); called by the scheduler and
  # after chat actions.
  def self.dispatch_due(now: Time.current, user: nil)
    scope = WorkItem.due(now)
    scope = scope.where(user: user) if user
    scope.includes(:user).filter_map do |item|
      next if item.active_run?

      director = item.user.director_role&.agent
      next item.block!("No director in your team.") unless director

      queue!(user: item.user, purpose: "director", work_item: item, agent: director)
    end
  end

  # --- Running one management run ----------------------------------------------------------------

  def initialize(run, **call_options)
    @run = run
    @user = run.user
    @item = run.work_item
    @call_options = call_options
  end

  def perform!
    if LEGACY.include?(@run.purpose)
      return TaskRunner.finish!(@run, AgentCall::Outcome.new("skipped", nil, "Managers were removed (spec 012).", nil))
    end

    agent = @run.agent
    return fail!("The #{role_name} is no longer set.") unless agent

    prompt = prompt_for(agent)
    outcome = AgentCall.new(@run, agent, prompt, **@call_options).call
    if outcome.state == "succeeded"
      begin
        apply!(parse(outcome.output))
      rescue Invalid, JSON::ParserError => e
        retry_prompt = AgentCall::Prompt.new(system: prompt.system, user: "#{prompt.user}\n\nYour previous answer was not accepted: #{e.message}\nAnswer again with only the JSON object.")
        outcome = AgentCall.new(@run, agent, retry_prompt, **@call_options).call
        if outcome.state == "succeeded"
          begin
            apply!(parse(outcome.output))
          rescue Invalid, JSON::ParserError => e2
            TaskRunner.finish!(@run, AgentCall::Outcome.new("failed", outcome.output, "Answer not accepted twice: #{e2.message}", nil))
            return fail!("the #{role_name}'s answer was not accepted twice (#{e2.message})")
          end
        end
      end
    end
    TaskRunner.finish!(@run, outcome)
    return fail!("the #{role_name} could not answer: #{outcome.error.to_s.truncate(300).chomp(".")}") unless outcome.state == "succeeded"

    answer_later_messages
    @run
  rescue StandardError => e
    Rails.logger.error("[management] run #{@run.id} failed: #{e.class}: #{e.message}")
    TaskRunner.finish!(@run, AgentCall::Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil)) unless @run.finished?
    fail!("something went wrong (#{e.class})")
  end

  private

  # R3: messages written while the director was answering get their own answer.
  def answer_later_messages
    return unless @run.purpose == "chat"

    self.class.chat!(@user) if @user.chat_messages.where(author: "user").where("created_at > ?", @run.started_at).exists?
  end

  def role_name = "director"

  # The answer is the first JSON object in the output (models sometimes wrap it in code fences).
  def parse(output)
    text = output.to_s
    first, last = text.index("{"), text.rindex("}")
    raise Invalid, "no JSON object in the answer" unless first && last && last > first

    data = JSON.parse(text[first..last])
    raise Invalid, "the answer must be a JSON object" unless data.is_a?(Hash)

    data
  end

  def apply!(data)
    case @run.purpose
    when "chat" then apply_chat!(data)
    when "director" then apply_plan!(data)
    end
  end

  # A failure: the item is blocked and the user is told in the chat (spec 011, resilience).
  def fail!(reason)
    if @item
      @item.reload
      @item.block!(reason.upcase_first) if @item.open?
      say("system", "\"#{@item.title}\" is blocked: #{reason}. Write to the director, or press Try again on the item.")
    else
      say("system", "No answer from the director: #{reason}.")
    end
    @run
  end

  def say(author, content, actions_summary: nil)
    ChatMessage.create!(user: @user, author: author, content: content.to_s.truncate(20_000), actions_summary: actions_summary, task_run: @run)
  end

  # --- Prompts -----------------------------------------------------------------------------------

  def prompt_for(agent)
    rules = case @run.purpose
            when "chat" then chat_prompt
            when "director" then plan_prompt
            end
    AgentCall::Prompt.new(system: agent.master_prompt, user: [ context_header, rules ].join("\n\n"))
  end

  def context_header
    now = Time.current
    "You work in Agentaro for #{@user.username}. Now: #{now.strftime("%A %-d %B %Y, %H:%M")} (#{Time.zone.name}).\nMode: #{@run.purpose}"
  end

  def team_members = @user.team_roles.members.includes(agent: :executor).order(:id).to_a

  def member_line(member)
    agent = member.agent
    "- Member id #{agent.id}: #{agent.name}, role: #{member.role_text || "-"}#{" — #{agent.description}" if agent.description.present?}#{" (not available)" unless agent.usable?}"
  end

  def team_text
    members = team_members
    [ "Team:", "- Director: #{@user.director_role&.agent&.name || "none"} (you)",
      *members.map { |m| member_line(m) }, ("  (no members yet)" if members.empty?) ].compact.join("\n")
  end

  def item_line(item)
    parts = [ "id #{item.id}", "\"#{item.title}\"", "state #{item.state}", "priority #{item.priority}" ]
    parts << "handle from #{item.handle_from.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.handle_from
    parts << "due #{item.due_on.iso8601}" if item.due_on
    "- " + parts.join(", ") + (item.description.present? ? "\n  #{item.description.truncate(500)}" : "")
  end

  def item_text(item)
    lines = [ "Work item: \"#{item.title}\" (priority #{item.priority})" ]
    lines << "Details: #{item.description}" if item.description.present?
    lines << "Handle from: #{item.handle_from.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.handle_from
    lines << "Due: #{item.due_on.iso8601} (end of day)" if item.due_on
    lines.join("\n")
  end

  def chat_prompt
    list = @user.work_items.where(state: WorkItem::OPEN + %w[planned]).listed.limit(50).map { |i| item_line(i) }
    history = @user.chat_messages.ordered.last(HISTORY).map { |m| "#{m.author == "user" ? @user.username : m.author.capitalize}: #{m.content}" }
    <<~PROMPT
      You are the director. #{@user.username} talks only to you. Keep their work list from the conversation; when an item's time comes, you will plan it for your team members.

      #{team_text}

      Work list (open and planned):
      #{list.presence&.join("\n") || "(empty)"}

      Conversation (latest last):
      #{history.join("\n")}

      Answer #{@user.username}'s latest messages. Reply with ONLY one JSON object, no other text:
      {"reply": "your message to #{@user.username}", "actions": [ ... ]}
      Actions (at most #{MAX_ACTIONS}, may be empty):
      {"type": "add_item", "title": "...", "description": "...", "handle_from": "YYYY-MM-DDTHH:MM" or null, "due_on": "YYYY-MM-DD" or null, "priority": "normal" or "high"}
      {"type": "update_item", "id": 1, "title": "...", "description": "...", "handle_from": ..., "due_on": ..., "priority": ...} (only items in state new or blocked; give only fields to change)
      {"type": "cancel_item", "id": 1}
      {"type": "reprioritize", "id": 1, "priority": "normal" or "high"}
      Items without handle_from are handled at once. Times are in #{Time.zone.name}.
    PROMPT
  end

  def plan_prompt
    now = Time.current
    busy = Task.occurrences_for(@user, now...(now + HORIZON)).reject(&:all_day?).first(100).map do |o|
      "- #{o.starts_at.in_time_zone.strftime("%a %Y-%m-%d %H:%M")}–#{o.ends_at.in_time_zone.strftime("%H:%M")}"
    end
    members = team_members.map { |m| member_line(m) }
    <<~PROMPT
      You are the director. Break the work item into steps for your team members and schedule them. Agentaro puts your plan in the calendar as it is; nobody reviews it, so make it right.

      #{item_text(@item)}

      Your team members (use only these ids):
      #{members.presence&.join("\n") || "(none)"}

      Busy times in the calendar (next 14 days):
      #{busy.presence&.join("\n") || "(none)"}

      Rules: 1 to #{MAX_STEPS} steps; each step 1 to 5760 minutes; start after now and within 14 days#{", not before the handle-from time" if @item.handle_from}#{", ending by the due date" if @item.due_on}; steps run at their start time, so order them in time.
      Reply with ONLY one JSON object, no other text:
      {"summary": "the plan in one or two sentences, for #{@user.username}", "steps": [{"title": "...", "description": "what to do and what to deliver", "agent": <member id>, "starts_at": "YYYY-MM-DDTHH:MM", "minutes": 30}]}
      or, if you cannot plan it or need #{@user.username}'s decision: {"blocked": "your question to #{@user.username}"}
    PROMPT
  end

  # --- Applying answers (R1: checked data only) ---------------------------------------------------

  def apply_chat!(data)
    reply = data["reply"].to_s.strip
    raise Invalid, "\"reply\" is missing" if reply.empty?

    actions = data["actions"] || []
    raise Invalid, "\"actions\" must be a list" unless actions.is_a?(Array)
    raise Invalid, "at most #{MAX_ACTIONS} actions" if actions.size > MAX_ACTIONS

    planned = actions.map { |action| check_action(action) } # all checked before any is applied
    summary = WorkItem.transaction { planned.map(&:call) }
    say("director", reply, actions_summary: summary.compact.join("\n").presence)
    self.class.dispatch_due(user: @user)
  end

  def check_action(action)
    raise Invalid, "each action must be an object" unless action.is_a?(Hash)

    case action["type"]
    when "add_item"
      attrs = item_attributes(action, require_title: true)
      item = @user.work_items.new(attrs.merge(position: @user.work_items.maximum(:position).to_i + 1))
      raise Invalid, "add_item: #{item.errors.full_messages.to_sentence}" unless item.valid?

      -> { item.save!; "Added to the list: #{item.title}" }
    when "update_item"
      item = own_item(action)
      raise Invalid, "update_item: item #{item.id} is #{item.state_label}; only new or blocked items can be changed" unless %w[new blocked].include?(item.state)

      item.assign_attributes(item_attributes(action).merge(state: "new", blocked_reason: nil))
      raise Invalid, "update_item: #{item.errors.full_messages.to_sentence}" unless item.valid?

      -> { item.save!; "Updated: #{item.title}" }
    when "cancel_item"
      item = own_item(action)
      raise Invalid, "cancel_item: item #{item.id} is already #{item.state_label}" if %w[done cancelled].include?(item.state)

      -> { item.cancel!; "Cancelled: #{item.title}" }
    when "reprioritize"
      item = own_item(action)
      raise Invalid, "reprioritize: priority must be normal or high" unless WorkItem::PRIORITIES.include?(action["priority"])

      -> { item.update!(priority: action["priority"]); "Priority #{action["priority"]}: #{item.title}" }
    else
      raise Invalid, "unknown action #{action["type"].inspect}"
    end
  end

  def own_item(action)
    @user.work_items.find_by(id: action["id"]) or raise Invalid, "#{action["type"]}: no item with id #{action["id"].inspect} on the list"
  end

  def item_attributes(action, require_title: false)
    attrs = {}
    attrs[:title] = action["title"].to_s if require_title || action.key?("title")
    attrs[:description] = action["description"].to_s.presence if action.key?("description")
    attrs[:priority] = action["priority"] if action.key?("priority") && action["priority"]
    raise Invalid, "priority must be normal or high" if attrs[:priority] && !WorkItem::PRIORITIES.include?(attrs[:priority])
    if action.key?("handle_from")
      attrs[:handle_from] = action["handle_from"].present? ? parse_time(action["handle_from"], "handle_from") : nil
    end
    if action.key?("due_on")
      attrs[:due_on] = action["due_on"].present? ? (Date.iso8601(action["due_on"].to_s) rescue raise(Invalid, "due_on must be YYYY-MM-DD")) : nil
    end
    attrs
  end

  def parse_time(value, field)
    Time.zone.parse(value.to_s) || raise(Invalid, "#{field} is not a date and time")
  rescue ArgumentError
    raise Invalid, "#{field} is not a date and time"
  end

  def apply_plan!(data)
    return block_with_question!(data["blocked"]) if data["blocked"].present?

    steps = data["steps"]
    raise Invalid, "\"steps\" must be a list of 1 to #{MAX_STEPS} steps" unless steps.is_a?(Array) && steps.size.between?(1, MAX_STEPS)

    members = team_members.to_h { |m| [ m.agent_id, m.agent ] }
    checked = steps.each_with_index.map { |step, i| check_step(step, i + 1, members) } # all checked before any is saved
    schedule!(checked, data["summary"].to_s.strip.truncate(2000).presence)
  end

  def check_step(step, number, members)
    raise Invalid, "step #{number} must be an object" unless step.is_a?(Hash)

    title = step["title"].to_s.strip
    raise Invalid, "step #{number}: title is missing or longer than 200 characters" if title.empty? || title.length > 200

    agent = members[step["agent"].to_i] or raise Invalid, "step #{number}: agent #{step["agent"].inspect} is not one of your team members"
    raise Invalid, "step #{number}: #{agent.name} is not available" unless agent.usable?

    starts = parse_time(step["starts_at"], "step #{number}: starts_at")
    minutes = Integer(step["minutes"], exception: false)
    raise Invalid, "step #{number}: minutes must be 1 to 5760" unless minutes&.between?(1, 5760)

    now = Time.current
    raise Invalid, "step #{number}: starts_at must be in the future" if starts <= now
    raise Invalid, "step #{number}: starts_at must be within 14 days" if starts > now + HORIZON
    raise Invalid, "step #{number}: starts before the handle-from time" if @item.handle_from && starts < @item.handle_from
    raise Invalid, "step #{number}: ends after the due date" if @item.due_on && starts + minutes.minutes > @item.due_on.in_time_zone.end_of_day

    { "title" => title, "description" => step["description"].to_s.truncate(5000), "agent" => agent.id,
      "starts_at" => starts.iso8601, "minutes" => minutes }
  end

  # Spec 012, G3: a checked plan becomes calendar tasks for the members, and the user is told in the chat.
  def schedule!(steps, summary)
    tasks = Task.transaction do
      steps.map do |step|
        starts = Time.zone.parse(step["starts_at"])
        Task.create!(user: @user, calendar: "private", title: step["title"], description: step["description"].presence,
                     starts_at: starts, ends_at: starts + step["minutes"].to_i.minutes, agent_id: step["agent"], work_item: @item)
      end
    end
    @item.update!(state: "planned", plan_summary: summary, blocked_reason: nil)
    first = tasks.min_by(&:starts_at)
    say("director", "#{summary || "Planned."}\n\nPlanned \"#{@item.title}\": #{tasks.size} step#{"s" unless tasks.size == 1}, first on #{first.starts_at.in_time_zone.strftime("%A %-d %B, %H:%M")}.")
  end

  def block_with_question!(question)
    @item.block!(question)
    say("director", "About \"#{@item.title}\": #{question}")
  end
end
