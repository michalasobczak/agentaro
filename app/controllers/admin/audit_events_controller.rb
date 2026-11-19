# Spec 003, G5: read-only view of the HTTP audit log.
class Admin::AuditEventsController < Admin::BaseController
  PAGE = 100

  def index
    scope = AuditEvent.order(id: :desc)
    scope = scope.where(username: params[:username]) if params[:username].present?
    scope = scope.where("path LIKE ?", "%#{AuditEvent.sanitize_sql_like(params[:path])}%") if params[:path].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(request_id: params[:request_id]) if params[:request_id].present?
    scope = scope.where(id: ...params[:before].to_i) if params[:before].present?
    @events = scope.limit(PAGE)
  end
end
