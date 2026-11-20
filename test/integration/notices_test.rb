require "test_helper"

# Spec 026: notices of blocked epics on every page; closing one is stored on the epic until it is blocked again.
class NoticesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @space = @user.spaces.create!(name: "Home", kind: "team")
    @item = @user.work_items.create!(title: "Backups", space: @space, state: "planned", started_at: 10.minutes.ago)
    sign_in(@user)
  end

  def notices
    get notices_path, headers: { "Accept" => "application/json" }
    assert_response :success
    response.parsed_body["blocked"]
  end

  test "G2, G3: a blocked epic is listed with its reason and actions; closing it keeps it closed until it is blocked again" do
    assert_equal [], notices
    @item.block!("Step 2 timed out")
    notice = notices.sole
    assert_equal [ "Backups", "Home", "Step 2 timed out" ], notice.values_at("title", "space", "reason")
    assert_equal [ work_item_path(@item), retry_work_item_path(@item), dismiss_notice_path(@item) ], notice.values_at("url", "retry_url", "dismiss_url")

    post dismiss_notice_path(@item)
    assert_response :no_content
    assert_equal [], notices, "closed on every device"
    @item.update!(state: "planned")
    @item.block!("Step 3 failed")
    assert_equal "Step 3 failed", notices.sole["reason"], "a new block shows again"
  end

  test "R4: only my own epics; another user's cannot be closed" do
    other = create_user(username: "other1")
    theirs = other.work_items.create!(title: "Theirs", space: other.spaces.create!(name: "X", kind: "team"))
    theirs.block!("No director")
    assert_equal [], notices
    post dismiss_notice_path(theirs)
    assert_response :not_found
    assert_nil theirs.reload.block_dismissed_at
  end

  test "G1, G2: every page carries the notice area and its script; the closed chat can blink" do
    get spaces_path
    assert_select "#notice-stack[data-notices][data-url='#{notices_path}'][data-turbo-permanent]"
    assert_select "script[src*=notices]"
    assert_select "[style]", 0
    assert_select "script:not([src])", 0
  end
end
