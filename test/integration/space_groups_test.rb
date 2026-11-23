require "test_helper"

# Spec 051: the endpoints, the Spaces page and the work panel; only the owner's spaces and groups.
class SpaceGroupsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @auta = @user.spaces.create!(kind: "project", name: "Gra Auta", goal: "Gra")
    @home = @user.spaces.create!(kind: "team", name: "Home")
    sign_in(@user)
  end

  test "G2, G3: create, place, order, rename and delete a group" do
    post space_groups_path, params: { space_group: { name: "Gry" } }
    gry = @user.space_groups.sole
    patch place_space_path(@auta), params: { group_id: gry.id, index: 1 }, as: :json
    assert_equal({ "ok" => true, "group_id" => gry.id, "position" => 1 }, response.parsed_body)
    other = @user.space_groups.create!(name: "Badania")
    patch order_space_groups_path, params: { ids: [ other.id, gry.id ] }, as: :json
    assert_equal [ "Badania", "Gry" ], @user.space_groups.ordered.pluck(:name)
    patch space_group_path(gry), params: { space_group: { name: "Gierki" } }, as: :json
    assert_equal "Gierki", gry.reload.name
    delete space_group_path(gry)
    assert_nil @auta.reload.space_group_id
    assert_redirected_to spaces_path
  end

  test "G1, G4: the page shows the groups in order, then the spaces without a group; the panel too; no inline style" do
    gry = @user.space_groups.create!(name: "Gry")
    @auta.place!(gry, 1)
    get spaces_path
    assert_select ".space-section", 2
    assert_select ".space-section[data-group-id='#{gry.id}'] .space-section-name", text: "Gry"
    assert_select ".space-section[data-group-id='#{gry.id}'] .space-card", text: /Gra Auta/
    assert_select ".space-section[data-group-id=''] .space-section-name", text: "Bez grupy"
    assert_select ".space-section[data-group-id=''] .space-card", text: /Home/
    assert_select ".space-card .badge", text: "project"
    assert_select "[data-space-layout].desktop-arrange"
    assert_select "[style]", 0
    get work_director_path, as: :json
    assert_equal [ [ "Gry", [ "Gra Auta" ] ], [ nil, [ "Home" ] ] ], response.parsed_body["groups"].map { |g| [ g["name"], g["spaces"].map { |s| s["name"] } ] }
  end

  test "S5: another user's spaces and groups are out of reach" do
    bob = create_user(username: "bob")
    theirs = bob.space_groups.create!(name: "Ich")
    their_space = bob.spaces.create!(kind: "team", name: "Ich")
    patch place_space_path(@auta), params: { group_id: theirs.id, index: 1 }, as: :json
    assert_response :not_found
    patch place_space_path(their_space), params: { index: 1 }, as: :json
    assert_response :not_found
    delete space_group_path(theirs)
    assert_response :not_found
    patch order_space_groups_path, params: { ids: [ theirs.id ] }, as: :json
    assert_equal 1, theirs.reload.position
  end

  # Owner fix (production, 2026-11-23): dragging "Gra Auta" into a group answered 422 — the move saves the group's
  # spaces, and two of them had working folders that no longer exist, so their validation refused the whole move.
  test "owner fix: a space whose folder is gone can still be moved; the folder is checked when it is set" do
    gone = Dir.mktmpdir("gone")
    @auta.update!(working_dir: gone)
    @home.update!(working_dir: Dir.mktmpdir("home"))
    FileUtils.rm_rf(gone)
    gry = @user.space_groups.create!(name: "Gry")
    patch place_space_path(@home), params: { group_id: gry.id, index: 1 }, as: :json
    patch place_space_path(@auta), params: { group_id: gry.id, index: 1 }, as: :json
    assert_response :success
    assert_equal [ "Gra Auta", "Home" ], gry.spaces.order(:position).pluck(:name)
    @auta.working_dir = Dir.mktmpdir("x") + "/missing"
    assert_not @auta.valid?, "a new folder must exist"
  end

  test "owner change: each group can fold to its label with its count; collapse and expand all are offered" do
    gry = @user.space_groups.create!(name: "Gry")
    @auta.place!(gry, 1)
    get spaces_path
    assert_select ".space-section[data-group-id='#{gry.id}'] button[data-space-fold][aria-controls='space-grid-#{gry.id}']"
    assert_select "#space-grid-#{gry.id}.space-grid"
    assert_select ".space-section[data-group-id='#{gry.id}'] .space-count", text: "1"
    assert_select ".space-section[data-group-id='#{gry.id}'] .space-preview .space-chip", text: "Gra Auta"
    assert_select ".space-section[data-group-id=''] button[data-space-fold][aria-controls='space-grid-none']"
    assert_select "[data-space-fold-all] button[data-fold-all=collapse]", text: "Collapse all"
    assert_select "[data-space-fold-all] button[data-fold-all=expand]", text: "Expand all"
    assert_select "[style]", 0
  end
end
