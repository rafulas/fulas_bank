# Fulas Bank: the budgets of Planes (see MonthBudget) at a glance: the amount
# of each one from the chosen month on, and an amount for any main category
# still without a budget (which gets a budget of its own). Naming a budget
# and choosing its categories is MonthPlans::BudgetGroupsController.
class MonthPlans::BudgetsController < ApplicationController
  before_action :set_month_budget

  def edit
    @groups = @month_budget.groups
    @amounts = @month_budget.amounts
    @estimate = MonthBudget::Estimate.new(Current.family, user: Current.user, month: @month_budget.month).amounts
                                     .transform_keys(&:to_s)
    @group_estimates = @groups.to_h { |group| [ group.id, group.chosen_ids.sum { |id| @estimate.fetch(id, 0) } ] }
    taken = @month_budget.taken_ids
    @free_categories = @month_budget.categories.reject do |category|
      taken.include?(category.id.to_s) || @month_budget.subcategories_of(category).any? { |sub| taken.include?(sub.id.to_s) }
    end
    # A first budget comes filled in with what is usually spent.
    @prefilled = @groups.empty? && @estimate.any?
  end

  def update
    @month_budget.save!(params.fetch(:amounts, ActionController::Parameters.new).permit(*@month_budget.groups.map(&:id)).to_h)
    @month_budget.create_for_categories!(params.fetch(:new_amounts, ActionController::Parameters.new).permit(*@month_budget.categories.map(&:id)).to_h)
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
