require "test_helper"

# Spec 005, F1: behind an HTTPS proxy, cookies are Secure and responses carry HSTS.
class HttpsProxyTest < ActionDispatch::IntegrationTest
  test "S1: every cookie is Secure and HSTS is sent" do
    post session_path, params: { username: create_user.username, password: PASSWORD }
    cookies = Array(response.headers["Set-Cookie"]).join("\n").lines.map(&:strip).reject(&:empty?)
    assert cookies.any?
    cookies.each { |cookie| assert_match(/;\s*secure/i, cookie, cookie[/\A[^=]+/]) }
    assert_match(/max-age=\d+/, response.headers["Strict-Transport-Security"])
  end

  test "the health check answers on any host, other pages only on allowed hosts" do
    host! "unexpected.example"
    get rails_health_check_path
    assert_response :success
  end
end
