# Fulas Bank: editing the budget from Planes (see MonthBudget): one amount
# per category, or per subcategory, from the chosen month on.
class MonthPlans::BudgetsController < ApplicationController
  before_action :set_month_budget

  def edit
    @amounts = @month_budget.amounts
    @estimate = MonthBudget::Estimate.new(Current.family, user: Current.user, month: @month_budget.month).amounts
    # A first budget comes filled in with what is usually spent.
    @prefilled = @amounts.empty? && @estimate.any?
    @amounts = @estimate.slice(*@month_budget.categories.map(&:id)) if @prefilled
  end

  def update
    @month_budget.save!(params.fetch(:amounts, ActionController::Parameters.new).permit(*@month_budget.category_ids).to_h)
    redirect_to month_plan_path(month: @month_budget.month.strftime("%Y-%m")), notice: t(".success")
  end

  private
    def set_month_budget
      @month_budget = MonthBudget.new(Current.family, user: Current.user, month: selected_month)
    end

    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      Date.current
    end
end
