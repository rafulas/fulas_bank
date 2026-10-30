# Fulas Bank: the "Planes" screen (see MonthPlan), one month at a time.
class MonthPlansController < ApplicationController
  def show
    # Fulas Bank: each loan's instalment, kept in step with the loan.
    Loan::InstallmentSync.new(Current.family, user: Current.user).sync!
    @plan = MonthPlan.new(Current.family, user: Current.user, month: selected_month)
    # Fulas Bank: the recurring payments as a calendar or as a timeline.
    @view = params[:view] == "timeline" ? "timeline" : "calendar"
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("month_plans.show.title"), nil ] ]
  end

  private
    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      Date.current
    end
end
