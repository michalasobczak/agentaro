require "test_helper"

# Owner fix: the scheduler starts at boot and its first runs build links, so the routes must be drawn before it starts
# (Rails 8 draws them lazily). Checked on the initializer's source, since the test process never boots a server.
class SchedulerBootTest < ActiveSupport::TestCase
  test "the routes are drawn before the scheduler starts" do
    source = Rails.root.join("config/initializers/task_scheduler.rb").read
    assert_operator source.index("reload_routes_unless_loaded"), :<, source.index("TaskScheduler.start")
    Rails.application.reload_routes_unless_loaded
    assert Rails.application.routes.url_helpers.respond_to?(:work_item_path)
  end
end
