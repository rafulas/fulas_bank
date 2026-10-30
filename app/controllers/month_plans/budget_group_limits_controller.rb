# Fulas Bank: the amounts of a budget set from a month on, from its screen:
# «Añadir límite futuro» and taking one away.
class MonthPlans::BudgetGroupLimitsController < ApplicationController
  before_action :set_group

  def create
    month = Date.strptime(params[:limit_month].to_s, "%Y-%m")
    @group.add_limit!(month, parse_amount(params[:amount]))
    redirect_to month_plan_budget_group_path(@group, month: return_month), notice: t(".success")
  rescue Date::Error
    redirect_to month_plan_budget_group_path(@group, month: return_month), alert: t(".invalid_month")
  end

  def destroy
    limit = @group.limits.find(params[:id])
    if @group.remove_limit!(limit)
      redirect_to month_plan_budget_group_path(@group, month: return_month), notice: t(".success")
    else
      redirect_to month_plan_budget_group_path(@group, month: return_month), alert: t(".first")
    end
  end

  private
    def set_group
      month_budget = MonthBudget.new(Current.family, user: Current.user)
      @group = month_budget.find_group(params[:budget_group_id]) || raise(ActiveRecord::RecordNotFound)
    end

    def return_month
      params[:month].presence
    end

    # An amount typed as «1.234,56» or «1234.56».
    def parse_amount(value)
      raw = value.to_s.strip.delete(" €")
      raw = raw.delete(".").tr(",", ".") if raw.include?(",")
      raw.to_d
    end
end
