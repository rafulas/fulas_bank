# Fulas Bank: the budgets of the coming months worked out from the forecast,
# each month with its own amounts. For every budget (BudgetGroup), what its
# categories usually spend on variable things that month (the same trimmed
# mean as "Gastos varios", with the month plans and the categories left out
# in «Ver cálculo») plus the recurring payments they have that month (so an
# annual insurance raises its own month only). Rounded up to whole euros.
#
# A spending main category in no budget gets one of its own, named after it.
#
# From then on the budget rules: the forecast takes each budget minus its
# recurring payments (Forecast::BudgetSource).
class Forecast::BudgetPlanner
  MONTHS = 60

  # A budget to plan: an existing one (`group`) or a main category that
  # will get one (`category`). `chosen_ids`: the categories it was given.
  Target = Data.define(:key, :group, :category, :chosen_ids)

  attr_reader :family, :user, :accounts, :today

  def initialize(family, user:, accounts:, today: Date.current)
    @family = family
    @user = user
    @accounts = accounts
    @today = today
  end

  # The months it writes: from next month, five years.
  def months
    first = today.beginning_of_month.next_month
    (0...MONTHS).map { |offset| first >> offset }
  end

  # { budget id, or main category id for a new budget => amount } for
  # `month`, positive amounts only.
  def amounts_for(month)
    targets.each_with_object({}) do |target, result|
      amount = amount_of(target, month)
      result[target.key] = amount if amount.positive?
    end
  end

  # Writes every month. @return [Integer] the months written
  def apply!
    BudgetGroup.transaction do
      targets.each do |target|
        amounts = months.index_with { |month| amount_of(target, month) }
        next if target.group.nil? && amounts.values.none?(&:positive?)

        group = target.group || create_group(target.category)
        group.replace_limits_from!(months.first, amounts)
      end
    end
    months.size
  end

  def targets
    @targets ||= begin
      existing = month_budget.groups.filter_map do |group|
        chosen = group.chosen_ids & spending_ids
        Target.new(key: group.id, group: group, category: nil, chosen_ids: chosen) if chosen.any?
      end

      taken = month_budget.taken_ids
      fresh = spending_mains.reject { |category| ([ category.id.to_s ] + child_ids(category.id.to_s)).any? { |id| taken.include?(id) } }
                            .map { |category| Target.new(key: category.id.to_s, group: nil, category: category, chosen_ids: [ category.id.to_s ]) }

      existing + fresh
    end
  end

  private
    def amount_of(target, month)
      variable = target.chosen_ids.sum { |id| variable_of(id, month) }.to_d
      recurring_ids = target.chosen_ids.flat_map { |id| [ id, *child_ids(id) ] } - plan.excluded_with_children
      (variable + recurring.total(month, recurring_ids)).ceil
    end

    # What a chosen category (with its subcategories) usually spends on
    # variable things in `month`: its month plan, when it has one.
    def variable_of(id, month)
      return 0.to_d if plan.excluded_with_children.include?(id)

      planned = plan.plan_for(month, id)
      return planned.amount if planned

      estimate.categories_monthly(month, [ id, *child_ids(id) ] - plan.excluded_with_children)
    end

    def create_group(category)
      group = family.budget_groups.create!(user_id: MonthBudget.owner_id(family, user), name: category.name,
                                           position: (month_budget.groups.map(&:position).max || -1) + 1)
      group.group_categories.create!(category: category)
      month_budget.groups << group
      group
    end

    def child_ids(id)
      @children ||= family.categories.where.not(parent_id: nil).pluck(:parent_id, :id)
                          .group_by(&:first).transform_keys(&:to_s)
                          .transform_values { |pairs| pairs.map { |pair| pair.last.to_s } }
      @children.fetch(id.to_s, [])
    end

    def month_budget
      @month_budget ||= MonthBudget.new(family, user: user, month: today)
    end

    def plan
      @plan ||= Forecast::VariablePlan.new(family, user: user, today: today)
    end

    # Without the budgets: they are what is being built.
    def estimate
      @estimate ||= Forecast::VariableEstimate.new(family, accounts: accounts, today: today, plan: plan)
    end

    def recurring
      @recurring ||= Forecast::CategoryRecurring.new(family)
    end

    # The main categories a budget can be given: spending ones, not income
    # nor savings and investments.
    def spending_mains
      @spending_mains ||= month_budget.categories.reject { |category| %w[income savings].include?(category.spending_class) }
    end

    def spending_ids
      @spending_ids ||= spending_mains.flat_map { |category| [ category.id.to_s, *child_ids(category.id.to_s) ] }
    end
end
