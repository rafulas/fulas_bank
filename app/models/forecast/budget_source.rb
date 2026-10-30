# Fulas Bank: the month's budgets as the forecast's "Gastos varios" uses them.
# The budget rules (see Forecast::VariableEstimate): for a main category with
# a budget, the forecast expects its budget minus the recurring payments it
# already has as lines of their own that month, never below zero. A
# category without a budget keeps the usual average.
#
# Only months after the current one: this month's estimate keeps what has
# already been spent in mind, which the average does.
class Forecast::BudgetSource
  attr_reader :family, :user, :today, :excluded_ids

  # `excluded_ids`: categories left out of the forecast (Forecast::VariablePlan),
  # whose budget is ignored too.
  def initialize(family, user:, today: Date.current, excluded_ids: [])
    @family = family
    @user = user
    @today = today
    @excluded_ids = Array(excluded_ids).map(&:to_s)
    @months = {}
  end

  # The budgets of the plan's user, without the categories the plan leaves
  # out. Nil without a user (no budgets to read).
  def self.for_plan(plan, today: Date.current)
    return unless plan&.user

    new(plan.family, user: plan.user, today: today, excluded_ids: plan.excluded_ids)
  end

  def recurring
    @recurring ||= Forecast::CategoryRecurring.new(family)
  end

  # { main category id => budget } for `month`, spending categories with an
  # amount only (not income nor savings and investments) (the budget of an earlier month carries on, as in Planes).
  def budgets(month)
    month = month.beginning_of_month
    return {} unless month > today.beginning_of_month

    @months[month] ||= MonthBudget.new(family, user: user, month: month).amounts
                                  .transform_keys(&:to_s)
                                  .select { |id, amount| amount.positive? && spending_main_ids.include?(id) && excluded_ids.exclude?(id) }
  end

  # { main category id => what the forecast expects of it besides its
  # recurring payments }.
  def variable_parts(month)
    expected = recurring.for(month)
    budgets(month).to_h { |id, amount| [ id, [ amount - expected.fetch(id, 0), 0 ].max.round(2) ] }
  end

  # The budgeted categories with their subcategories: what the average
  # leaves out that month, as the budget replaces it.
  def covered_ids(month)
    ids = budgets(month).keys
    return [] if ids.empty?

    ids | family.categories.where(parent_id: ids).pluck(:id).map(&:to_s)
  end

  private
    def spending_main_ids
      @spending_main_ids ||= family.categories.roots.reject(&:analytics_neutral?)
                                   .reject { |category| %w[income savings].include?(category.spending_class) }
                                   .map { |category| category.id.to_s }
    end
end
