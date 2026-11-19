require "securerandom"

module Agentaro
  # Spec 003: records every HTTP request in the audit log (AuditEvent).
  #
  # Runs first in the middleware stack, so static files, host-authorization rejections and errors are
  # recorded too. It assigns the request id (replacing any id sent by the client), so audit rows,
  # data changes (spec 004) and Rails logs share one id. Sensitive values are filtered with the
  # application's filter_parameters. Logging fails open (R1): the response is never affected.
  class AuditMiddleware
    BODY_LIMIT = 10_000 # bytes stored per request body (spec 003, G2)

    def initialize(app)
      @app = app
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      request_id = SecureRandom.uuid
      env["HTTP_X_REQUEST_ID"] = request_id
      status = 500
      status, headers, body = @app.call(env)
      [ status, headers, body ]
    ensure
      record(env, request_id, status, started)
      AuditRetention.run_if_due if Rails.application.config.x.audit_auto_prune
    end

    private

    def record(env, request_id, status, started)
      request = ActionDispatch::Request.new(env)
      session = resolve_session(request, env)
      AuditEvent.append!(
        request_id: request_id,
        user_id: env["agentaro.user_id"] || session&.user_id,
        username: env["agentaro.username"] || session&.user&.username,
        session_id: env["agentaro.session_id"] || session&.id,
        remote_addr: env["REMOTE_ADDR"],
        forwarded_for: env["HTTP_X_FORWARDED_FOR"],
        user_agent: env["HTTP_USER_AGENT"].to_s[0, 500],
        http_method: request.request_method,
        host: env["HTTP_HOST"].to_s[0, 255],
        path: request.path,
        query: filtered_query(request),
        body: filtered_body(request),
        status: status.to_i,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3)
      )
    rescue StandardError => e
      Rails.logger.error("[audit] could not record request #{request_id}: #{e.class}: #{e.message}")
    end

    # The authentication layer stores the session it resolved; otherwise read the session cookie.
    def resolve_session(request, env)
      return nil if env["agentaro.session_id"]

      id = request.cookie_jar.signed[:session_id]
      id && Session.find_by(id: id)
    rescue StandardError
      nil
    end

    def filtered_query(request)
      query = request.filtered_path.split("?", 2)[1]
      query&.byteslice(0, BODY_LIMIT)
    end

    def filtered_body(request)
      return nil if request.get? || request.head?

      params = request.request_parameters
      text = params.present? ? parameter_filter.filter(params).to_json : raw_body_summary(request)
      text&.byteslice(0, BODY_LIMIT)
    rescue StandardError
      raw_body_summary(request)
    end

    def raw_body_summary(request)
      length = request.content_length.to_i
      length.positive? ? "[#{length} bytes, #{request.media_type || "unknown type"}, not stored]" : nil
    end

    def parameter_filter
      @parameter_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end
  end
end
