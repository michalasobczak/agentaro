module ApplicationHelper
  # Inline SVG icons (24×24, stroke) — no icon font, no external files (spec 006).
  ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/><path d="M10 21v-6h4v6"/>',
    sessions: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m10.8 12.2 8.7-8.7M17 6l2.5 2.5M14.5 8.5 17 11"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-6 6.5-6s5.9 2.4 6.5 6"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14.3c1.7.8 2.8 2.9 3 5.7"/>',
    log: '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
    history: '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 7v5l3 2"/>',
    logout: '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><path d="M10 17l5-5-5-5M15 12H3"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    link: '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
    shield: '<path d="M12 3 4.5 6v6c0 4.4 3.2 7.9 7.5 9 4.3-1.1 7.5-4.6 7.5-9V6L12 3Z"/><path d="m9 12 2 2 4-4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    chevron_left: '<path d="m15 6-6 6 6 6"/>',
    chevron_right: '<path d="m9 6 6 6-6 6"/>',
    repeat: '<path d="M17 2l3 3-3 3"/><path d="M4 11V9a4 4 0 0 1 4-4h12"/><path d="M7 22l-3-3 3-3"/><path d="M20 13v2a4 4 0 0 1-4 4H4"/>',
    agent: '<rect x="4" y="7" width="16" height="13" rx="3"/><path d="M12 3v4M9 12h.01M15 12h.01M9.5 16h5M2 12v3M22 12v3"/>',
    send: '<path d="M4 12 20 4l-4 16-4-7-8-1Z"/><path d="m12 13 8-9"/>',
    chat: '<path d="M4 5h16v11H9l-5 4V5Z"/><path d="M8 9.5h8M8 12.5h5"/>',
    list: '<path d="M9 6h11M9 12h11M9 18h11"/><path d="m3.5 6 1 1 2-2M3.5 12l1 1 2-2M3.5 18l1 1 2-2"/>',
    brain: '<path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1V5a2 2 0 0 0-3-1z"/><path d="M15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1"/>',
    org: '<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="3" y="16" width="6" height="5" rx="1"/><rect x="15" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M6 16v-4h12v4"/>',
    play: '<path d="M7 4.5v15l12-7.5-12-7.5Z"/>',
    chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 10h4v4h-4zM9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    pin: '<path d="M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21Z"/><circle cx="12" cy="9.5" r="2.5"/>',
    close: '<path d="M6 6l12 12M18 6 6 18"/>',
    expand: '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
    verify: '<path d="M12 3 4.5 6v5.5c0 4.5 3.2 8.4 7.5 9.5 4.3-1.1 7.5-5 7.5-9.5V6L12 3Z"/><path d="m8.8 12 2.2 2.2 4.4-4.6"/>',
    voice: '<path d="M4 10v4M8 7v10M12 4v16M16 7v10M20 10v4"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7"/>',
    mic_off: '<path d="M15 9.5V6a3 3 0 0 0-5.6-1.5M9 9v2a3 3 0 0 0 4.7 2.5"/><path d="M18.5 11a6.5 6.5 0 0 1-1 3.4M5.5 11a6.5 6.5 0 0 0 10 5.5M12 17.5V21M8.5 21h7M3 3l18 18"/>',
    new_chat:'<path d="M4 5h16v11H9l-5 4V5Z"/><path d="M12 8v5M9.5 10.5h5"/>',
    settings: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
    board: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M15 4v16"/><path d="M5.5 8h2M11.5 8h2M17.5 8h1"/>'
  }.freeze

  def icon(name, css: "icon")
    tag.svg(ICONS.fetch(name).html_safe, class: css, viewBox: "0 0 24 24", "aria-hidden": "true")
  end

  def nav_link(label, path, icon_name, active: current_page?(path), css: nil)
    link_to path, class: [ ("active" if active), css ].compact.join(" "), "aria-current": (active ? "page" : nil) do
      safe_join([ icon(icon_name), tag.span(label) ])
    end
  end

  def badge(text, kind = nil)
    tag.span(text, class: [ "badge", kind ].compact.join(" "))
  end

  def role_badge(user) = user.admin? ? badge("admin", "accent") : badge("user")

  def account_badge(user)
    return badge("deactivated", "bad") unless user.active?
    return badge("locked", "warn") if user.locked?

    badge("active", "ok")
  end

  def totp_badge(user)
    return badge("off") unless user.otp_required?

    user.otp_enrolled? ? badge("on", "ok") : badge("not set up", "warn")
  end

  def status_class(status) = "status-#{status.to_i / 100}xx"

  def initials(user) = user.username.delete("._-")[0, 2]

  def page_header(title, subtitle = nil, &actions)
    content_for(:title, "#{title} · Agentaro")
    tag.div(class: "page-header") do
      safe_join([
        tag.div { safe_join([ tag.h1(title), (tag.p(subtitle) if subtitle) ].compact) },
        (tag.div(class: "page-actions", &actions) if actions)
      ].compact)
    end
  end

  # Owner fix after spec 013: where a page sits — Spaces › space › epic › step › run. Crumbs are
  # [label, path] pairs; the last one is the current page and is not a link.
  def breadcrumbs(*crumbs)
    *links, current = crumbs.compact
    items = links.map { |label, path| tag.li(link_to(label, path)) } + [ tag.li(current.first, "aria-current": "page") ]
    tag.nav(tag.ol(safe_join(items)), class: "breadcrumbs", "aria-label": "Breadcrumb")
  end

  def space_crumbs(space) = [ [ "Spaces", spaces_path ], [ space.name, space_path(space) ] ]

  # Spec 025, R2: what deleting an archived space takes with it.
  def space_delete_confirmation(space)
    counts = space.purge_counts
    text = "Delete #{space.name} with #{pluralize(counts[:epics], "epic")}, their steps and runs?"
    text += " #{pluralize(counts[:running], "step")} in progress will be stopped." if counts[:running].positive?
    "#{text} This cannot be undone."
  end
  def epic_crumbs(item) = [ *space_crumbs(item.space), [ item.title, work_item_path(item) ] ]

  # A step of an epic (calendar task with a work item): its crumbs, or nil for an ordinary task.
  def step_crumbs(task)
    return unless task.work_item && task.work_item.user_id == current_user.id

    [ *epic_crumbs(task.work_item), [ task.title, edit_task_path(task) ] ]
  end

  # Admin tools are for desktop and tablet; phones get this note instead (spec 006, G5).
  def desktop_only_note
    tag.div(class: "callout mobile-note") do
      safe_join([ icon(:info), tag.div { "Admin tools are designed for larger screens. Open this page on a tablet or computer." } ])
    end
  end

  # Spec 011: states of work items.
  def item_state_badge(item)
    return badge(item.pausing? ? "pausing" : "paused", "warn") if item.paused? # spec 048, G5
    kind = { "planned" => "accent", "running" => "warn", "done" => "ok", "blocked" => "bad", "cancelled" => nil, "new" => nil }[item.board_state]
    badge(item.board_state.tr("_", " "), kind)
  end

  # Spec 011/012: what a management run did. Before spec 012 a "director" run of an item chose a manager.
  # Spec 030, G7: one line of a model call's numbers.
  def trace_call_summary(call)
    tokens = [ call.input_tokens && "#{number_with_delimiter(call.input_tokens)} in", call.output_tokens && "#{number_with_delimiter(call.output_tokens)} out" ].compact
    [ call.state&.tr("_", " "), [ call.model, call.effort && "effort #{call.effort}" ].compact.join(", ").presence,
      ("#{tokens.join(" / ")} tokens" if tokens.any?), ("$#{format("%.4f", call.cost_usd)}" if call.cost_usd),
      ("#{call.duration.round(1)} s" if call.duration), (pluralize(call.turns, "turn") if call.turns) ].compact.join(" · ")
  end

  def run_purpose_label(run)
    case run.purpose
    when "chat" then "chat"
    when "memory" then "the brain read a message" # spec 031
    when "epic_step" then run.epic_step ? "step #{run.epic_step.position}: #{run.epic_step.title}" : "step" # spec 016
    when "director" then run.work_item&.runs&.exists?(purpose: "manager") ? "director chose a manager" : "director planned"
    when "manager" then "manager planned (before spec 012)"
    when "review" then "director reviewed the plan (before spec 012)"
    end
  end

  # The floating chat (owner fix after spec 011): for users with a director. Spec 020: on every page, the
  # Director page too — there it stays hidden unless voice mode runs in it (Q1), so moving to that page never
  # drops a conversation.
  def chat_dock_director
    return unless signed_in?
    current_user.director_role&.agent
  end

  # Spec 011: a chat message as the chat page shows it (rendered by the server and by chat.js alike).
  # Spec 023, R10/R12: the author's icon (letter, tone or fixed kind, agent id for the status dot) for non-user messages.
  def chat_message_json(message)
    director = message.user.director_role&.agent
    verifier = message.user.verifier_role&.agent if message.author == "verifier"
    agent = { "director" => director, "verifier" => verifier }[message.author]
    icon = case message.author
           when "director" then { icon_letter: agent_initials(director&.name || "Director"), icon_kind: "director" }
           when "verifier" then { icon_letter: agent_initials(verifier&.name || "Verifier"), icon_kind: "verifier" }
           when "system" then { icon_letter: "A", icon_kind: "system" }
           else {}
           end
    { id: message.id, author: message.author,
      name: { "user" => "You", "director" => director&.name || "Director", "verifier" => "#{verifier&.name || "Verifier"} · verifier", "system" => "Agentaro" }[message.author],
      content: message.content, actions: message.actions_summary, reply_to: message.reply_to_id,
      kind: ("summary" if message.author == "director" && message.task_run_id && message.task_run&.purpose == "summary"), # spec 045, G4
      time: l(message.created_at, format: "%H:%M"), day: l(message.created_at.to_date, format: :long),
      **icon, icon_tone: nil, icon_agent: agent&.id }
  end

  # --- Spec 023: agent icons and busy/free status ---------------------------------------------------------------

  # R10: the first letter of the name, upper case; "?" when the name does not start with a letter.
  # Owner fix after spec 023 ("wystarczy inicjały, max 2"): the first letters of the first two words of the name,
  # e.g. "Discovery Agent" → "DA", "Anna" → "A"; a name that does not start with a letter gets "?" (R10).
  def agent_initials(name)
    words = name.to_s.strip.split(/[\s_.-]+/)
    return "?" unless words.first.to_s[0]&.match?(/\p{L}/)

    words.filter_map { |word| word[0] if word[0]&.match?(/\p{L}/) }.first(2).join.upcase
  end

  def agent_tone(agent) = "tone-#{agent.id % 8}"

  # R10/R11: a circle with a letter; `kind` (director, verifier, system) or `tone` sets the colour. `status` is an
  # entry of AgentStatus.json; its dot is hidden unless `show_dot` (and updated in place by the scripts, R12).
  def agent_icon(letter, kind: nil, tone: nil, size: "bubble", agent_id: nil, status: nil)
    classes = [ "agent-icon", "is-#{size}", (kind ? "is-#{kind}" : tone) ].compact.join(" ")
    dot = (status_dot(status) if agent_id)
    tag.span(class: classes, "aria-hidden": "true", data: { agent_icon: agent_id }) { safe_join([ letter, dot ].compact) }
  end

  def status_dot(status)
    status ||= { status: "free", label: "free", show_dot: false }
    tag.span(class: "status-dot is-#{status[:status]}", title: status[:label], hidden: !status[:show_dot])
  end

  # The icon of a chat message (nil for the user's own).
  def chat_message_icon(data, statuses)
    return unless data[:icon_kind]

    agent_icon(data[:icon_letter], kind: data[:icon_kind], agent_id: data[:icon_agent], status: statuses[data[:icon_agent]])
  end

  # G3: the status badge and the activities on the Team page (text, never colour alone — R11). Spec 036, S3: the badge
  # says the load, e.g. "2/6 in progress", and "busy · 6/6 in progress" only at the limit.
  def agent_status_badge(status)
    status ||= { status: "free", headline: "free", label: "free", show_dot: true, activities: [] }
    # The director and verifier show it only while they run something (R11); hidden, so the poll can show it.
    tag.span(class: "agent-status", data: { agent_status: status[:id] }, hidden: status[:show_dot] == false) do
      safe_join([ badge(status[:headline] || status[:status], AGENT_STATUS_TONES[status[:status]]), agent_activity_list(status[:activities]) ])
    end
  end

  AGENT_STATUS_TONES = { "busy" => "warn", "working" => "accent" }.freeze # the same in app.js

  def agent_activity_list(activities)
    tag.span(class: "agent-activities") do
      safe_join(Array(activities).map { |a| tag.span(agent_activity_text(a), class: "agent-activity muted small", title: a[:title]) }, " ")
    end
  end

  # G4, R5: the chat strip — the load ("free · 0/6 in progress", "2/6 in progress", "busy · 6/6 in progress", spec 036),
  # then the first own activity and "+N more".
  def agent_strip_label(status)
    activities = Array(status[:activities])
    head = status[:headline] || status[:status]
    return head if activities.empty?

    "#{head} · #{agent_activity_text(activities.first)}#{" · +#{activities.size - 1} more" if activities.size > 1}"
  end

  # Spec 036: the folded chat strip — "3 tasks in progress · 1 of 2 busy" (busy: at the limit).
  def team_strip_count(members)
    running = members.sum { |m| m.dig(:capacity, :running).to_i }
    "#{running} #{running == 1 ? "task" : "tasks"} in progress · #{members.count { |m| m[:status] == "busy" }} of #{members.size} busy"
  end

  # "World review · step 2/4: Collect evidence · for 3 min" (G2, R4, R7) — the same text team_status.js builds.
  def agent_activity_text(activity)
    started = activity[:started_at] && Time.zone.parse(activity[:started_at])
    where = activity[:cancelled] ? "finishing a step of a #{activity[:epic_state] == "cancelled" ? "cancelled" : "closed"} epic: #{activity[:epic]}" : activity[:epic]
    [ where, "step #{activity[:step]}/#{activity[:of]}: #{activity[:title].to_s.truncate(AgentStatus::TITLE_LIMIT)}",
      ("for #{AgentStatus.elapsed(started)}" if started) ].compact.join(" · ")
  end

  # Spec 043, G2: an executor's subscription limit as its tool last reported it (Claude Code, Codex only).
  def usage_limit_text(executor)
    return tag.span("—", class: "muted") unless %w[claude_code codex].include?(executor.preset)

    summary = UsageLimit.summary(executor)
    reached = UsageLimit.reached_note(executor)
    return tag.span("not read yet", class: "muted small") unless summary || reached

    safe_join([
      (badge(reached, "bad") if reached),
      (tag.span(summary) if summary),
      (tag.span("read #{time_ago_in_words(executor.usage_read_at)} ago", class: "muted small") if executor.usage_read_at)
    ].compact, " ")
  end
end
