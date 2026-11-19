# Spec 010: the scheduler runs inside the web server only — not in the console, rake tasks or tests.
Rails.application.config.after_initialize do
  Agentaro::TaskScheduler.start if Rails.application.config.x.task_scheduler && defined?(Rails::Server)
end
