require "test_helper"

# Spec 034: the Recurring pages, the space page and the calendar (G2, G8), the director's chat actions (G2, R2)
# and access (R1).
class RecurringOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Serwery", kind: "team")
    sign_in(@user)
  end

  def params(**attrs)
    { recurring_order: { space_id: @space.id, title: "Przegląd <b>backupów</b>", kind: "weekly", weekdays: %w[1 5], at_time: "08:00",
                         starts_on: Date.current.iso8601, report: "always" }.merge(attrs) }
  end

  test "G2 (owner fix): orders are a part of their space — added, listed, edited, paused, resumed and removed from the space page; escaped; no inline style" do
    get space_path(@space)
    assert_select "nav a", text: "Recurring", count: 0
    assert_select "#recurring a[href='#{new_recurring_order_path(space_id: @space.id)}']"
    get new_recurring_order_path(space_id: @space.id)
    assert_select "select[name='recurring_order[space_id]'] option[selected][value='#{@space.id}']"
    post recurring_orders_path, params: params
    order = @user.recurring_orders.sole
    assert_equal [ "1,5", "active" ], [ order.weekdays, order.state ]
    assert_redirected_to space_path(@space, anchor: "order-#{order.id}")
    follow_redirect!
    assert_select "#recurring #order-#{order.id}", text: /Przegląd <b>backupów<\/b>.*every Mon, Fri at 08:00/m
    assert_select "[style]", 0

    patch recurring_order_path(order), params: params(kind: "daily", at_time: "06:30")
    assert_equal [ "daily", "06:30" ], order.reload.values_at(:kind, :at_time)
    patch pause_recurring_order_path(order)
    assert_equal [ "paused", nil ], order.reload.values_at(:state, :next_at)
    patch resume_recurring_order_path(order)
    assert order.reload.next_at
    delete recurring_order_path(order)
    assert_redirected_to space_path(@space, anchor: "recurring")
    assert_not RecurringOrder.exists?(order.id)
  end

  test "R2: an invalid schedule is refused with the reason" do
    post recurring_orders_path, params: params(kind: "hourly", every_hours: "0")
    assert_response :unprocessable_entity
    assert_select ".flash", text: /1 to 168 hours/
    assert_equal 0, RecurringOrder.count
  end

  test "R1: another user's orders and spaces cannot be used or changed" do
    other = create_user(username: "other1")
    theirs_space = other.spaces.create!(name: "Theirs", kind: "team")
    theirs = other.recurring_orders.create!(space: theirs_space, title: "Theirs", kind: "daily", at_time: "08:00")
    [ -> { get new_recurring_order_path(space_id: theirs_space.id) }, -> { get edit_recurring_order_path(theirs) }, -> { patch pause_recurring_order_path(theirs) }, -> { delete recurring_order_path(theirs) } ].each do |request|
      request.call
      assert_response :not_found
    end
    assert_equal "active", theirs.reload.state
    post recurring_orders_path, params: params(space_id: theirs_space.id)
    assert_response :unprocessable_entity
    assert_equal 0, @user.recurring_orders.count
  end

  test "G8: the space page lists its orders and the calendar shows coming occurrences, read-only" do
    order = @user.recurring_orders.create!(space: @space, title: "Przegląd", kind: "daily", at_time: "08:00")
    get space_path(@space)
    assert_select "#recurring #order-#{order.id}"
    get calendar_path(view: "week", date: (Date.current + 1).iso8601)
    assert_select "a.e-upcoming[href='#{space_path(@space, anchor: "order-#{order.id}")}']", minimum: 1
  end

  # --- G2: the chat ------------------------------------------------------------------------------------

  def with_director_answer(*answers)
    Dir.mktmpdir do |bin|
      answers.each_with_index { |a, i| File.write(File.join(bin, "answer-#{i + 1}"), a.to_json) }
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nn=$(cat #{bin}/n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > #{bin}/n\ncat #{bin}/answer-$n\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def chat(content, *answers)
    @user.chat_messages.create!(author: "user", content: content)
    with_director_answer(*answers) do
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    end
    @user.chat_messages.where(author: "director").order(:id).last
  end

  test "S1: \"co poniedziałek o 8 przejrzyj backupy\" creates an order said back in words; the director sees it and can pause it" do
    add = [ { type: "add_recurring", space: @space.id, title: "Przegląd backupów", schedule: { kind: "weekly", time: "08:00", weekdays: [ 1 ] } } ]
    reply = chat("Co poniedziałek o 8 przejrzyj backupy w Serwery.", { reply: "Dobrze: co poniedziałek o 8:00.", actions: add }, { reply: "ok", actions: add })
    order = @user.recurring_orders.sole
    assert_equal [ "weekly", "1", "08:00" ], order.values_at(:kind, :weekdays, :at_time)
    assert_match "Recurring order added: Przegląd backupów, every Mon at 08:00", reply.actions_summary

    pause = [ { type: "pause_recurring", id: order.id } ]
    chat("Wstrzymaj przegląd backupów.", { reply: "Wstrzymuję.", actions: pause }, { reply: "ok", actions: pause })
    assert_equal "paused", order.reload.state
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
    assert_match "- id #{order.id}, \"Przegląd backupów\", space #{@space.id} (Serwery), every Mon at 08:00", prompt
  end

  test "R2: a schedule under an hour from the chat is refused; nothing is created" do
    add = [ { type: "add_recurring", space: @space.id, title: "Spam", schedule: { kind: "hourly", time: "00:00", every_hours: 0 } } ]
    chat("Rób to co minutę.", { reply: "Dobrze.", actions: add }, { reply: "ok", actions: add }, { reply: "ok", actions: add })
    assert_equal 0, RecurringOrder.count
  end
end
