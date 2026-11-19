class ApplicationController < ActionController::Base
  # Request id shared by the audit log (spec 003) and the data changelog (spec 004).
  prepend_before_action { Current.request_id = request.request_id }

  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Rate limits are kept in memory per process (spec 002, R3); Rails.cache may be a null store.
  RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::NullStore.new : ActiveSupport::Cache::MemoryStore.new
end
