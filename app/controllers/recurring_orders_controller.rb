# Spec 034: recurring orders — a part of their space (owner fix: no separate page; they are listed on the space's
# page), with a form, pause, resume and delete. Only the owner's own orders and spaces (R1).
class RecurringOrdersController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  before_action :set_order, except: %i[new create]

  def new
    @order = current_user.recurring_orders.new(space: current_user.spaces.find(params[:space_id]), kind: "weekly", weekdays: "1", at_time: "08:00",
                                               starts_on: Time.zone.today)
  end

  def create
    @order = current_user.recurring_orders.new(order_params)
    return render(:new, status: :unprocessable_entity) unless @order.save

    redirect_to back_to_space, notice: "Recurring order added: #{@order.schedule_text}."
  end

  def edit; end

  def update
    return render(:edit, status: :unprocessable_entity) unless @order.update(order_params)

    redirect_to back_to_space, notice: "Saved: #{@order.schedule_text}."
  end

  def destroy
    @order.destroy!
    redirect_to space_path(@order.space, anchor: "recurring"), notice: "Removed: #{@order.title}. Its epics stay."
  end

  def pause
    @order.update!(state: "paused")
    redirect_to back_to_space, notice: "Paused: #{@order.title}."
  end

  def resume
    return redirect_to(back_to_space, alert: @order.errors.full_messages.to_sentence) unless @order.update(state: "active")

    redirect_to back_to_space, notice: "Resumed: #{@order.title}."
  end

  private

  def set_order = @order = current_user.recurring_orders.find(params[:id])
  def back_to_space = space_path(@order.space, anchor: "order-#{@order.id}")

  def order_params
    attrs = params.expect(recurring_order: [ :space_id, :title, :description, :kind, :at_time, :month_day, :every_hours, :starts_on, :ends_on, :report, { weekdays: [] } ])
    attrs[:weekdays] = Array(attrs[:weekdays]).join(",") if attrs.key?(:weekdays)
    attrs[:space_id] = current_user.spaces.find_by(id: attrs[:space_id])&.id if attrs.key?(:space_id) # R1: own spaces only
    attrs
  end
end
