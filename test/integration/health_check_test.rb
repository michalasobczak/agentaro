require "test_helper"

# Spec 001, S3: the blank application boots and reports healthy.
class HealthCheckTest < ActionDispatch::IntegrationTest
  test "health check returns 200" do
    get rails_health_check_path
    assert_response :success
  end
end
