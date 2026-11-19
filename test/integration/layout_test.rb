require "test_helper"

# Spec 006: responsive layout. Phones (CSS, < 900px) hide everything marked desktop-only; this checks
# the markup that the stylesheet relies on (S2) and that pages stay free of inline styles (CSP, S3).
class LayoutTest < ActionDispatch::IntegrationTest
  test "sign-in pages use the centered card without navigation" do
    get new_session_path
    assert_select "body.auth .auth-card form"
    assert_select "aside.sidebar", 0
  end

  test "signed-in pages have the sidebar and the phone menu with the same links" do
    sign_in(create_user)
    get root_path
    assert_select "aside.sidebar nav a", text: "My sessions"
    assert_select "header.topbar details nav a", text: "My sessions"
    assert_select "meta[name=viewport]"
  end

  test "S2: admin links are desktop-only and admin pages show the phone note" do
    admin = create_user(username: "root1", role: "admin")
    sign_in(admin)
    get root_path
    %w[Users Audit\ log Data\ changes].each do |label|
      assert_select "header.topbar nav a.desktop-only", text: label
      assert_select "header.topbar nav a:not(.desktop-only)", text: label, count: 0
    end
    [ admin_users_path, new_admin_user_path, admin_user_path(admin), admin_audit_events_path, admin_data_changes_path ].each do |path|
      get path
      assert_response :success
      assert_select ".mobile-note", 1, path
      assert_select "main .card.desktop-only", { minimum: 1 }, path
    end
  end

  test "S3: no inline styles or scripts in any template (blocked by the Content-Security-Policy)" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].select { |f| File.read(f).match?(/style=|<script/) }
    assert_empty offenders
  end
end
