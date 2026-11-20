# Spec 011, corrected by spec 012: the director runs like any agent (spec 010) but answers in JSON.
# Agents propose, Agentaro applies (R1): every answer is parsed, checked against the user's own list, team
# and the rules, and only then applied. An invalid answer is retried once with the errors.
#
# Purposes: "chat" (the director answers the user, spec 011 G1) and "director" (the director plans a new epic
# for its members, spec 012 G2; spec 016: at once, as an ordered list of steps without times). "manager" and "review" exist only in runs from before spec 012.
class ManagementRunner
  MAX_STEPS = 10
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
  # Spec 019: the user asks the verifier to check the conversation. One at a time, not while the director writes.
  # except: the chat run that asks for it (owner fix: an active verifier follows every answer of the director).
  def self.verify!(user, except: nil)
    verifier = user.verifier_role&.agent
    return nil unless verifier
    return nil if TaskRun.where(user: user, purpose: %w[chat verify], state: %w[queued running]).where.not(id: except&.id).exists?

    queue!(user: user, purpose: "verify", agent: verifier)
  end

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
    return verify!(agent) if @run.purpose == "verify"

    prompt = prompt_for(agent)
    outcome = AgentCall.new(@run, agent, prompt, **@call_options).call(on_text: stream_reply)
    if outcome.state == "succeeded"
      begin
        apply!(parse(outcome.output))
      rescue Invalid, JSON::ParserError => e
        retry_prompt = AgentCall::Prompt.new(system: prompt.system, user: "#{prompt.user}\n\nYour previous answer was not accepted: #{e.message}\nAnswer again with only the JSON object.")
        ReplyStream.clear(@run.id)
        outcome = AgentCall.new(@run, agent, retry_prompt, **@call_options).call(on_text: stream_reply)
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
  ensure
    ReplyStream.clear(@run.id) # R4: nothing of the partial reply stays
  end

  private

  # Spec 017, G4: while the director answers the user, the "reply" so far is kept in memory for the chat to show.
  def stream_reply
    return unless @run.purpose == "chat"

    run_id = @run.id
    ->(text) { ReplyStream.write(run_id, ReplyStream.partial_reply(text)) }
  end

  # R3: messages written while the director was answering get their own answer.
  def answer_later_messages
    return unless @run.purpose == "chat"

    self.class.chat!(@user) if @user.chat_messages.where(author: "user").where("created_at > ?", @run.started_at).exists?
  end

  def role_name = @run.purpose == "verify" ? "verifier" : "director"

  # Spec 019, G4/R1: the verifier answers in plain text; it is posted as a comment and nothing is applied.
  def verify!(agent)
    outcome = AgentCall.new(@run, agent, AgentCall::Prompt.new(system: agent.master_prompt, user: [ context_header, verify_prompt ].join("\n\n")), **@call_options).call
    TaskRunner.finish!(@run, outcome)
    return fail!("the verifier could not answer: #{outcome.error.to_s.truncate(300).chomp(".")}") unless outcome.state == "succeeded"

    comment = outcome.output.to_s.strip.truncate(4000)
    return fail!("the verifier gave no comment") if comment.empty?

    say("verifier", comment)
    @run
  end

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
      say("system", "No answer from the #{role_name}: #{reason}.")
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

  # Owner fix after spec 017: the user's chosen conversation language, or the language of their latest message.
  def reply_language
    name = User::LANGUAGE_NAMES[@user.chat_language]
    text = name ? "Write your reply in #{name}." : "Write your reply in the language of #{@user.username}'s latest message (for example Polish when they write Polish)."
    spoken? ? "#{text} #{spoken_style}" : text
  end

  # Owner fixes: short spoken answers ("żeby odpowiadali krócej w rozmowie głosowej"), in a human way ("żeby agent
  # odpowiadał bardziej po ludzku, jak GPT w rozmowie głosowej").
  def spoken_style
    <<~STYLE.squish
      #{@user.username} is talking by voice and hears your reply read aloud: keep it short — at most #{@run.purpose == "verify" ? 2 : 3} short spoken
      sentences, no lists, headings, Markdown or emoji. Sound like a person in a relaxed phone call, not like a report: warm and natural,
      everyday words, contractions and short reactions where they fit ("Jasne", "Mhm, rozumiem", "Dobra"). Answer the point first, then at
      most one short question back if something is unclear. Never read out ids, numbers of epics or spaces, technical states or time stamps;
      say times and amounts the way people say them ("za kwadrans druga", "jakieś dwie minuty temu"). Do not repeat what #{@user.username}
      just said, and do not announce what you are going to say.
    STYLE
  end

  # Owner fix: the latest message of the user came from voice mode.
  def spoken? = (@spoken ||= (@user.chat_messages.current.where(author: "user").ordered.last&.spoken? ? :yes : :no)) == :yes

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

  # Spec 013, G3/G4: in the chat, spaces meet only as names, goals and epic titles — no descriptions or plans.
  def item_line(item)
    parts = [ "id #{item.id}", "\"#{item.title}\"", "space #{item.space_id}", "state #{item.running? ? "running" : item.state}", "priority #{item.priority}" ]
    parts << "starts #{item.starts_at.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.starts_at && !item.started_at
    parts << "started #{item.started_at.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.started_at
    parts << "finished #{item.finished_at.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.finished_at
    parts << "due #{item.due_on.iso8601}" if item.due_on
    lines = [ "- " + parts.join(", ") ]
    lines << "  blocked: #{item.blocked_reason.truncate(300)}" if item.state == "blocked" && item.blocked_reason.present?
    lines.concat(step_lines(item))
    lines.join("\n")
  end

  # Owner fix ("najwyraźniej director nie widzi postępów pracy agentów"): live progress of an epic's steps — state,
  # agent, how long, and errors. Titles and states only, like the rest of the chat (spec 013, G3); results stay on
  # the epic's page.
  def step_lines(item)
    now = Time.current
    item.epic_steps.includes(:agent, :runs).map do |step|
      run = step.last_run
      took = if run&.started_at && run.finished_at then " in #{duration(run.finished_at - run.started_at)}"
             elsif run&.started_at && step.state == "running" then " for #{duration(now - run.started_at)} so far"
             end
      error = " — #{run.error.to_s.truncate(200)}" if run && EpicStep::STOPPED.include?(step.state) && run.error.present?
      "  step #{step.position} \"#{step.title}\" (#{step.agent&.name || "agent removed"}): #{step.state_label}#{took}#{error}"
    end
  end

  def duration(seconds)
    seconds = seconds.to_i
    seconds < 90 ? "#{seconds} s" : "#{(seconds / 60.0).round} min"
  end

  # Open and planned epics, and those finished in the last day (so the director can report them).
  def visible_items
    recent = @user.work_items.where(state: %w[done cancelled]).where("updated_at > ?", 1.day.ago)
    @user.work_items.where(state: WorkItem::OPEN + %w[planned]).or(recent).listed.limit(50)
  end

  def spaces_text
    spaces = @user.spaces.active.ordered.to_a
    return "Spaces: (none yet; a new item goes to \"#{Space::DEFAULT_NAME}\")" if spaces.empty?

    [ "Spaces (active):", *spaces.map { |s| "- id #{s.id}: \"#{s.name}\" — #{s.purpose_line.truncate(320)}" } ].join("\n")
  end

  # Spec 013, G3: everything about one epic comes from its own space only.
  def space_text(item)
    space = item.space
    others = space.work_items.where.not(id: item.id).where.not(state: "cancelled").listed.limit(30).map { |i| "- \"#{i.title}\" (#{i.state})" }
    [ "Space: \"#{space.name}\" (#{space.kind} space)", ("Space goal: #{space.goal}" if space.project?), ("Space description: #{space.description}" if space.description.present?),
      "Other epics in this space:", others.presence&.join("\n") || "(none)" ].compact.join("\n")
  end

  def item_text(item)
    lines = [ "Work item (epic): \"#{item.title}\" (priority #{item.priority})" ]
    lines << "Details: #{item.description}" if item.description.present?
    lines << "Starts: #{item.starts_at.in_time_zone.strftime("%Y-%m-%d %H:%M")}" if item.starts_at
    lines << "Due: #{item.due_on.iso8601} (end of day)" if item.due_on
    lines.join("\n")
  end

  def chat_prompt
    list = visible_items.includes(:space).map { |i| item_line(i) }
    # Spec 015: archived conversations are left out.
    history = @user.chat_messages.current.ordered.last(HISTORY).map { |m| "#{m.author == "user" ? @user.username : m.author.capitalize}: #{m.content}" }
    <<~PROMPT
      You are the director. #{@user.username} talks only to you. Keep their work list from the conversation; when an item's time comes, you will plan it for your team members.

      #{team_text}

      #{spaces_text}

      Work list (open, planned and running, and finished in the last day), with the live progress of each step — this is current; report it, do not tell #{@user.username} to look it up:
      #{list.presence&.join("\n") || "(empty)"}

      Conversation (latest last; "Verifier" is a second model #{@user.username} may ask to check you — take its comments seriously, answer them honestly):
      #{history.join("\n")}

      Answer #{@user.username}'s latest messages. #{reply_language} These instructions are in English only for you. Messages may come from speech recognition, so forgive small transcription errors.
      Reply with ONLY one JSON object, no other text:
      {"reply": "your message to #{@user.username}", "actions": [ ... ]}
      Actions (at most #{MAX_ACTIONS}, may be empty):
      {"type": "add_item", "space": <space id, or the name of a space added in this reply>, "title": "...", "description": "...", "starts_at": "YYYY-MM-DDTHH:MM" or null, "due_on": "YYYY-MM-DD" or null, "priority": "normal" or "high"}
      {"type": "update_item", "id": 1, "space": ..., "title": "...", "description": "...", "starts_at": ..., "due_on": ..., "priority": ...} (give only fields to change; items in state new or blocked can change everything, planned items that have not started only title, starts_at and priority)
      {"type": "add_space", "kind": "project" or "team", "name": "...", "goal": "what #{@user.username} wants to achieve (project spaces only)", "description": "what the space is about; for a team space, what it takes care of"}
      {"type": "update_space", "id": 1, "kind": ..., "name": "...", "goal": "...", "description": "...", "working_dir": "/absolute/path" or null} (give only fields to change; a project space needs a goal; working_dir is the folder on this computer its steps work in)
      A project space works towards a goal; a team space has no goal and takes care of ongoing work.
      {"type": "cancel_item", "id": 1}
      {"type": "reprioritize", "id": 1, "priority": "normal" or "high"}
      You plan each new item at once as steps for your team members. An item starts at its starts_at, or at once when it has none; then its steps run one after another without waiting. Times are in #{Time.zone.name}.
      Every item belongs to a space. When it is not clear which space a new item belongs to, do not guess: ask in your reply and add nothing.
    PROMPT
  end

  # Spec 019, G3: the conversation, the director's latest answer with what Agentaro applied, and the user's spaces
  # and open epics (names, goals, titles only — spec 013, G3).
  def verify_prompt
    list = visible_items.includes(:space).map { |i| item_line(i) }
    history = @user.chat_messages.current.ordered.last(HISTORY).map do |m|
      who = m.author == "user" ? @user.username : m.author.capitalize
      "#{who}: #{m.content}#{"\n  [applied by Agentaro: #{m.actions_summary}]" if m.actions_summary.present?}"
    end
    <<~PROMPT
      You are the verifier: a second model asked by #{@user.username} to check what their director (another AI model) said. You only comment; you change nothing.

      #{spaces_text}

      Work list (open, planned and running, and finished in the last day), with the live progress of each step — this is current; report it, do not tell #{@user.username} to look it up:
      #{list.presence&.join("\n") || "(empty)"}

      Conversation (latest last):
      #{history.join("\n")}

      Check the director's latest answer: facts, logic, plans, and any claim that something was done or checked. Say plainly what is wrong, doubtful or unverified, and what to ask or check instead. If it holds up, say so briefly. Be concrete and short: at most 8 sentences, plain text, no headings. #{reply_language.sub("your reply", "your comment")}
    PROMPT
  end

  # Spec 016, G2: an ordered list of steps without times; they run one after another from the epic's start.
  def plan_prompt
    members = team_members.map { |m| member_line(m) }
    start = @item.starts_at ? "at #{@item.starts_at.in_time_zone.strftime("%A %-d %B %Y, %H:%M")}" : "at once"
    <<~PROMPT
      You are the director. Break the work item into steps for your team members. Agentaro runs your plan as it is; nobody reviews it, so make it right.
      The item starts #{start}. Its steps run one after another, each as soon as the previous one has finished, and each step receives the answers of the earlier steps. So order them so that each step builds on the ones before.

      #{item_text(@item)}

      #{space_text(@item)}

      Your team members (use only these ids):
      #{members.presence&.join("\n") || "(none)"}

      Rules: 1 to #{MAX_STEPS} steps, in the order they should run; each step for one member. Write the summary, titles and descriptions in the language of the work item.
      Reply with ONLY one JSON object, no other text:
      {"summary": "the plan in one or two sentences, for #{@user.username}", "steps": [{"title": "...", "description": "what to do and what to deliver", "agent": <member id>}]}
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

    @new_spaces = {} # spaces added in this reply, by name, so items of the same reply can name them
    planned = actions.map { |action| check_action(action) } # all checked before any is applied
    summary = WorkItem.transaction { planned.map(&:call) }
    say("director", reply, actions_summary: summary.compact.join("\n").presence)
    self.class.verify!(@user, except: @run) if @user.verifier_active? # queued before this run ends, so "writing" never drops in between
    self.class.dispatch_due(user: @user)
  end

  def check_action(action)
    raise Invalid, "each action must be an object" unless action.is_a?(Hash)

    case action["type"]
    when "add_item"
      attrs = item_attributes(action, require_title: true)
      space = action.key?("space") ? find_space(action["space"], "add_item") : (@new_spaces["#default"] ||= Space.default_for(@user))
      raise Invalid, "add_item: \"space\" is required — you have several spaces (or ask which one)" unless space

      item = @user.work_items.new(attrs.merge(space: space, position: @user.work_items.maximum(:position).to_i + 1))
      raise Invalid, "add_item: #{item.errors.full_messages.to_sentence}" unless item.valid?

      -> { item.save!; "Added to the list: #{item.title}" }
    when "update_item"
      item = own_item(action)
      waiting = item.state == "planned" && item.started_at.nil? # spec 016: a planned epic that has not started yet
      raise Invalid, "update_item: item #{item.id} is #{item.state_label}#{" and has started" if item.state == "planned"}; it cannot be changed" unless %w[new blocked].include?(item.state) || waiting

      if waiting
        extra = action.keys - %w[type id title starts_at priority]
        raise Invalid, "update_item: item #{item.id} is planned; only title, starts_at and priority can change (not #{extra.join(", ")})" if extra.any?

        item.assign_attributes(item_attributes(action))
      else
        item.assign_attributes(item_attributes(action).merge(state: "new", blocked_reason: nil))
        item.space = find_space(action["space"], "update_item") if action.key?("space") # spec 013, Q5: only new or blocked items move
      end
      raise Invalid, "update_item: #{item.errors.full_messages.to_sentence}" unless item.valid?

      -> { item.save!; "Updated: #{item.title}" }
    when "add_space"
      space = @user.spaces.new(kind: action["kind"].presence || "project", name: action["name"], goal: action["goal"], description: action["description"])
      raise Invalid, "add_space: #{space.errors.full_messages.to_sentence}" unless space.valid?
      raise Invalid, "add_space: \"#{space.name}\" twice in one reply" if @new_spaces.key?(space.name.downcase)

      @new_spaces[space.name.downcase] = space
      -> { space.save!; "New space: #{space.name}" }
    when "update_space"
      space = @user.spaces.find_by(id: action["id"]) or raise Invalid, "update_space: no space with id #{action["id"].inspect}"
      space.assign_attributes(action.slice("kind", "name", "goal", "description", "working_dir"))
      raise Invalid, "update_space: #{space.errors.full_messages.to_sentence}" unless space.valid?

      -> { space.save!; "Space updated: #{space.name}" }
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

  # A space of the user by id, or one added earlier in the same reply by name (spec 013, G6).
  def find_space(value, action)
    space = @new_spaces[value.to_s.strip.downcase] if value.is_a?(String)
    space ||= @user.spaces.find_by(id: value) if value.to_s.match?(/\A\d+\z/)
    space ||= @user.spaces.find_by("LOWER(name) = ?", value.to_s.strip.downcase) if value.is_a?(String)
    raise Invalid, "#{action}: no space #{value.inspect} among your spaces" unless space
    raise Invalid, "#{action}: space \"#{space.name}\" is archived" unless space.active?

    space
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
    key = action.key?("starts_at") ? "starts_at" : ("handle_from" if action.key?("handle_from")) # handle_from: the name before spec 016
    if key
      attrs[:starts_at] = action[key].present? ? parse_time(action[key], "starts_at") : nil
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

    { "title" => title, "description" => step["description"].to_s.truncate(5000), "agent" => agent.id }
  end

  # Spec 016, G2: a checked plan becomes the epic's ordered steps; the epic is planned and starts at its time.
  def schedule!(steps, summary)
    EpicStep.transaction do
      @item.epic_steps.where(state: "pending").destroy_all # a re-plan replaces steps that never ran
      base = @item.epic_steps.maximum(:position).to_i
      steps.each_with_index do |step, i|
        @item.epic_steps.create!(position: base + i + 1, title: step["title"], description: step["description"].presence, agent_id: step["agent"])
      end
      @item.update!(state: "planned", plan_summary: summary, blocked_reason: nil, finished_at: nil)
    end
    start = @item.starts_at && @item.starts_at > Time.current ? "starts #{@item.starts_at.in_time_zone.strftime("%A %-d %B, %H:%M")}" : "starting now"
    # Owner fix after spec 017: Agentaro's own note goes under the message (actions), so the director's words stay
    # in the user's language and only they are spoken.
    say("director", summary || @item.title, actions_summary: "Planned \"#{@item.title}\": #{steps.size} step#{"s" unless steps.size == 1}, #{start}; they run one after another.")
    StepChain.start_due(user: @user)
  end

  def block_with_question!(question)
    @item.block!(question)
    say("director", question, actions_summary: "Question about \"#{@item.title}\"") # the director's words only (owner fix after spec 017)
  end
end
