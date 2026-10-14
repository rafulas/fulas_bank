# Fulas Bank: the "Planes" screen (see MonthPlan), one month at a time.
class MonthPlansController < ApplicationController
  def show
    @plan = MonthPlan.new(Current.family, user: Current.user, month: selected_month)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("month_plans.show.title"), nil ] ]
  end

  private
    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      Date.current
    end
end
