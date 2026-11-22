# Spec 010: the scheduler runs inside the web server only — not in the console, rake tasks or tests.
Rails.application.config.after_initialize do
  if Rails.application.config.x.task_scheduler && defined?(Rails::Server)
    # Owner fix: Rails 8 draws routes on the first request; a review run picked up right after a restart built a link
    # (work_item_path) before that and failed with NoMethodError, blocking the epic. The routes are drawn first.
    Rails.application.reload_routes_unless_loaded
    Agentaro::TaskScheduler.start
  end
end
