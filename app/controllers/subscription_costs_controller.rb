# Fulas Bank: the "Suscripciones" page (see SubscriptionsOverview). Not to
# be confused with SubscriptionsController, Sure's own paid plan.
class SubscriptionCostsController < ApplicationController
  def index
    @overview = SubscriptionsOverview.new(Current.family, user: Current.user)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("subscription_costs.index.title"), nil ] ]
  end

  # «Añadir suscripción»: pick which recurring payment is a subscription, or
  # open the form for a new one.
  def pick
    @candidates = SubscriptionsOverview.new(Current.family, user: Current.user).other_candidates(limit: nil)
    render layout: turbo_frame_request? ? false : "application"
  end

  # Marks a subscription as one that could be dropped, or unmarks it.
  def could_drop
    series = accessible_series.find(params[:id])
    SubscriptionsOverview.toggle_could_drop!(Current.user, series.id, ActiveModel::Type::Boolean.new.cast(params[:could_drop]))
    redirect_to subscription_costs_path
  end

  # Cancels a subscription: it stops counting from today.
  def cancel
    series = accessible_series.typed_subscription.find(params[:id])
    SubscriptionsOverview.cancel!(series)
    redirect_to subscription_costs_path, notice: t(".success", name: series.display_name)
  end

  # Takes a cancelled subscription up again.
  def resume
    series = accessible_series.typed_subscription.find(params[:id])
    SubscriptionsOverview.resume!(series)
    redirect_to subscription_costs_path, notice: t(".success", name: series.display_name)
  end

  # Turns another recurring payment into a subscription.
  def mark
    series = accessible_series.find(params[:id])
    series.update!(bill_type: "subscription")
    redirect_to subscription_costs_path, notice: t(".success", name: series.display_name)
  end

  private
    def accessible_series
      Current.family.recurring_transactions.accessible_by(Current.user)
    end
end
