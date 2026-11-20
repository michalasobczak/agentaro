# Spec 026: blocked epics the user has not closed the notice of, polled by notices.js on every page; closing a
# notice is stored on the epic, so it does not come back on another device until the epic is blocked again.
class NoticesController < ApplicationController
  MAX = 5

  def index
    items = current_user.work_items.block_notices.includes(:space).order(updated_at: :desc).limit(MAX)
    render json: { blocked: items.map { |item| notice_json(item) } }
  end

  def dismiss
    item = current_user.work_items.find(params[:id])
    item.update!(block_dismissed_at: Time.current) if item.state == "blocked"
    head :no_content
  end

  private

  def notice_json(item)
    { id: item.id, key: "#{item.id}-#{item.updated_at.to_i}", title: item.title, space: item.space.name,
      reason: item.blocked_reason.to_s.truncate(300), url: work_item_path(item),
      retry_url: retry_work_item_path(item), dismiss_url: dismiss_notice_path(item) }
  end
end
