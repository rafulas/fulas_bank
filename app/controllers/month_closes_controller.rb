# Fulas Bank: the guided month close (see MonthClose).
class MonthClosesController < ApplicationController
  def index
    redirect_to month_close_path(MonthClose.latest(Current.family, user: Current.user))
  end

  def show
    recap = Recap.from_param(Current.family, params[:id], user: Current.user)
    raise ActiveRecord::RecordNotFound unless recap&.month? && recap.started?

    @month_close = MonthClose.new(recap)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ @month_close_title = t(".title", month: l(recap.start_date, format: "%B")), nil ] ]
  end
end
