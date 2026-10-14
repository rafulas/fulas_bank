# Fulas Bank: editing the budget from Planes (see MonthBudget): one amount
# per category, from the chosen month on.
class MonthPlans::BudgetsController < ApplicationController
  before_action :set_month_budget

  def edit
    @amounts = @month_budget.amounts
    @averages = monthly_averages
  end

  def update
    @month_budget.save!(params.fetch(:amounts, ActionController::Parameters.new).permit(*@month_budget.categories.map(&:id)).to_h)
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

    # What was usually spent on each category, as a guide: the app's own
    # monthly median from the month's budget rows, when it has them.
    def monthly_averages
      budget = Current.family.budgets.find_by(start_date: Budget.period_for(@month_budget.month, family: Current.family).first,
                                              user_id: Current.family.personal_budgets? ? Current.user.id : nil)
      return {} unless budget

      budget.budget_categories.reject(&:subcategory?).to_h { |row| [ row.category_id, row.median_monthly_expense_money ] }
    rescue StandardError
      {}
    end
end
