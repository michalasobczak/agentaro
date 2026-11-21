require "test_helper"

# Owner fix ("potrzebuję też dark mode"): Auto, Light or Dark, chosen in the sidebar and saved on the account.
class ThemeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in(@user)
  end

  test "the choice is saved on the account and set on every page; unknown values change nothing" do
    get spaces_path
    assert_select "body[data-theme=auto]"
    assert_select ".sidebar .theme-switch button.is-on[aria-pressed=true]", text: "Auto"
    patch account_theme_path, params: { theme: "dark" }, headers: { "HTTP_REFERER" => spaces_url }
    assert_redirected_to spaces_url
    assert_equal "dark", @user.reload.theme
    get calendar_path
    assert_select "body[data-theme=dark]"
    assert_select ".theme-switch button.is-on", text: "Dark"
    patch account_theme_path, params: { theme: "pink; x" }
    assert_equal "dark", @user.reload.theme
    assert_select "[style]", 0
  end

  # Spec 028: Light and the return to Auto also persist across pages.
  test "light and back to auto are saved and set on the next page" do
    patch account_theme_path, params: { theme: "light" }, headers: { "HTTP_REFERER" => spaces_url }
    assert_equal "light", @user.reload.theme
    get root_path
    assert_select "body[data-theme=light]"
    assert_select ".theme-switch button.is-on", text: "Light"
    patch account_theme_path, params: { theme: "auto" }
    assert_equal "auto", @user.reload.theme
    get calendar_path
    assert_select "body[data-theme=auto]"
    assert_select ".theme-switch button.is-on", text: "Auto"
  end
end
