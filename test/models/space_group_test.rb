require "test_helper"

# Spec 051: groups of spaces, the order of groups and of spaces within them.
class SpaceGroupTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @auta, @psi, @slodziaki, @home = [ %w[project Gra\ Auta], %w[project Gra\ Psi\ Patrol], %w[project Gra\ Słodziaki], %w[team Home] ].map do |kind, name|
      @user.spaces.create!(kind: kind, name: name, goal: ("Gra" if kind == "project"))
    end
    @gry = @user.space_groups.create!(name: "Gry")
  end

  def layout = SpaceGroup.layout(@user, @user.spaces.reload.to_a).map { |g, spaces| [ g&.name, spaces.map(&:name) ] }

  test "S1, G1: a space dragged into a group is there, in order; the rest is out of every group" do
    @auta.place!(@gry, 1)
    @slodziaki.place!(@gry, 2)
    @psi.place!(@gry, 2)
    assert_equal [ [ "Gry", [ "Gra Auta", "Gra Psi Patrol", "Gra Słodziaki" ] ], [ nil, [ "Home" ] ] ], layout
    assert_equal [ 1, 2, 3 ], [ @auta, @psi, @slodziaki ].map { |s| s.reload.position }
  end

  test "S2, R2: moving within a group and between groups keeps both groups dense" do
    [ @auta, @psi, @slodziaki ].each_with_index { |s, i| s.place!(@gry, i + 1) }
    @slodziaki.place!(@gry, 1)
    assert_equal [ "Gra Słodziaki", "Gra Auta", "Gra Psi Patrol" ], layout.first.last
    @auta.place!(nil, 1)
    assert_equal [ [ "Gry", [ "Gra Słodziaki", "Gra Psi Patrol" ] ], [ nil, [ "Gra Auta", "Home" ] ] ], layout
    assert_equal [ 1, 2 ], @gry.spaces.order(:position).pluck(:position)
  end

  test "S2: groups take the owner's order" do
    badania = @user.space_groups.create!(name: "Badania")
    SpaceGroup.arrange!(@user, [ badania.id, @gry.id ])
    assert_equal [ "Badania", "Gry", nil ], layout.map(&:first)
  end

  test "S3: deleting a group moves its spaces out of every group and changes nothing else" do
    @auta.place!(@gry, 1)
    item = @user.work_items.create!(title: "Wydajność", space: @auta)
    @gry.destroy!
    assert_nil @auta.reload.space_group_id
    assert_equal @auta, item.reload.space
  end

  test "S5, R1: a space never joins another user's group; names are unique per owner" do
    other = create_user(username: "bob").space_groups.create!(name: "Gry")
    @auta.space_group = other
    assert_not @auta.valid?
    assert_not @user.space_groups.new(name: "gry").valid?
  end

  def apply(text, actions)
    @user.chat_messages.create!(author: "user", content: text)
    ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:apply_chat!, { "reply" => "OK", "actions" => actions })
    @user.chat_messages.last
  end

  test "S4, G5: \"dodaj Cerbeto do grupy Badania\" adds the group and moves the space; the director sees the groups" do
    cerbeto = @user.spaces.create!(kind: "project", name: "Cerbeto", goal: "Model")
    reply = apply("Dodaj Cerbeto do nowej grupy Badania", [ { "type" => "add_group", "name" => "Badania" }, { "type" => "move_space", "space" => cerbeto.id, "group" => "Badania" } ])
    assert_equal "Badania", cerbeto.reload.space_group&.name
    assert_match "New group: Badania", reply.actions_summary
    assert_match "Cerbeto → Badania", reply.actions_summary
    text = ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:spaces_text)
    assert_match(/Group id \d+ "Badania":\n- id #{cerbeto.id}: "Cerbeto"/, text)
    assert_match "Not in a group:", text
  end

  test "negative, G5: without words about groups nothing is arranged" do
    error = (apply("Co słychać?", [ { "type" => "add_group", "name" => "X" } ]); nil) rescue $!
    assert_match "has not asked in their message to arrange spaces in groups", error.message
    assert_equal [ "Gry" ], @user.space_groups.pluck(:name)
  end
end
