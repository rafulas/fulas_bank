# Fulas Bank: the month's budgets as the forecast's "Gastos varios" uses them.
# The budget rules (see Forecast::VariableEstimate): for a budget with an
# amount that month (BudgetGroup, any categories it groups), the forecast
# expects that amount minus the recurring payments its categories already
# have as lines of their own that month, never below zero. A category in no
# budget keeps the usual average.
#
# Only months after the current one: this month's estimate keeps what has
# already been spent in mind, which the average does.
class Forecast::BudgetSource
  attr_reader :family, :user, :today, :excluded_ids

  # `excluded_ids`: categories left out of the forecast (Forecast::VariablePlan),
  # with their subcategories; they do not count in any budget either.
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

    new(plan.family, user: plan.user, today: today, excluded_ids: plan.excluded_with_children)
  end

  def recurring
    @recurring ||= Forecast::CategoryRecurring.new(family)
  end

  def groups
    @groups ||= MonthBudget.new(family, user: user, month: today).groups
  end

  def find_group(id)
    groups.find { |group| group.id == id.to_s }
  end

  # The categories of a budget the forecast counts: spending ones (not
  # income nor savings and investments), not left out.
  def covered_for(group)
    group.expanded_category_ids & (spending_ids - excluded_ids)
  end

  # The budget a category counts in, if any.
  def group_for(category)
    groups.find { |group| covered_for(group).include?(category.id.to_s) }
  end

  # { budget id => amount } for `month`, budgets with an amount and
  # spending categories only.
  def budgets(month)
    month = month.beginning_of_month
    return {} unless month > today.beginning_of_month

    @months[month] ||= groups.each_with_object({}) do |group, result|
      amount = group.limit_for(month)
      result[group.id] = amount if amount.positive? && covered_for(group).any?
    end
  end

  # { budget id => what the forecast expects of it besides its recurring
  # payments }.
  def variable_parts(month)
    budgets(month).to_h do |id, amount|
      [ id, [ amount - recurring_of(find_group(id), month), 0 ].max.round(2) ]
    end
  end

  def recurring_of(group, month)
    recurring.total(month, covered_for(group))
  end

  # The categories of the month's budgets: what the average leaves out
  # that month, as the budgets replace it.
  def covered_ids(month)
    budgets(month).keys.flat_map { |id| covered_for(find_group(id)) }.uniq
  end

  private
    def spending_ids
      @spending_ids ||= begin
        mains = family.categories.roots.reject(&:analytics_neutral?)
                      .reject { |category| %w[income savings].include?(category.spending_class) }
        ids = mains.map(&:id)
        (ids + family.categories.where(parent_id: ids).reject(&:analytics_neutral?).map(&:id)).map(&:to_s)
      end
    end
end
