# Fulas Bank: links a movement to one of the recurring series (fixed, bill or
# subscription), or makes a new one from it, from its detail panel (see
# SubscriptionLink).
class Transactions::SubscriptionsController < ApplicationController
  before_action :set_entry

  def update
    series_id = params.dig(:subscription, :series_id).presence
    series = series_id && Current.family.recurring_transactions.accessible_by(Current.user).find(series_id)
    SubscriptionLink.new(@entry).link!(series)

    redirect_back_or_to transaction_path(@entry), notice: t(".success")
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, RecurringTransaction::Allocator::OverAllocationError
    redirect_back_or_to transaction_path(@entry), alert: t(".failed")
  end

  def create
    series = SubscriptionLink.new(@entry).create!(name: params.dig(:subscription, :name), kind: params.dig(:subscription, :kind).presence || "subscription")

    redirect_back_or_to transaction_path(@entry), notice: t(".success", name: series.display_name)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_back_or_to transaction_path(@entry), alert: t(".failed")
  end

  private
    def set_entry
      @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
      require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))
    end
end
