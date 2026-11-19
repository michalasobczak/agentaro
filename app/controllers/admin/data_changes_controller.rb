# Spec 004, G5: read-only view of the data changelog, filterable to one record's history.
class Admin::DataChangesController < Admin::BaseController
  PAGE = 100

  def index
    scope = DataChange.order(id: :desc)
    scope = scope.where(record_type: params[:record_type]) if params[:record_type].present?
    scope = scope.where(record_id: params[:record_id]) if params[:record_id].present?
    scope = scope.where(actor: params[:actor]) if params[:actor].present?
    scope = scope.where(request_id: params[:request_id]) if params[:request_id].present?
    scope = scope.where(id: ...params[:before].to_i) if params[:before].present?
    @changes = scope.limit(PAGE)
  end
end
