# Fulas Bank: the budget as Bilance does it. One amount a month for each
# category, repeated every month until it is changed; the total is the sum.
#
# Underneath it uses the app's monthly budgets (Budget and BudgetCategory),
# so nothing is lost, but without their steps: no total typed first, no
# "copy last month", no rollover or moving money between categories.
#
# - A month with no budget of its own takes the amounts of the latest month
#   before it that has one (`ensure!`).
# - Saving a month's amounts applies them to that month and to the later
#   months already created, never to earlier ones.
# - Amounts go on main categories; each covers its subcategories' spending.
class MonthBudget
  attr_reader :family, :user, :month

  def initialize(family, user:, month: Date.current)
    @family = family
    @user = user
    @month = month.beginning_of_month
  end

  # The main categories a budget can be given, in the user's order.
  def categories
    @categories ||= family.categories.roots.reject(&:analytics_neutral?).sort_by(&:display_sort_key)
  end

  # { category_id => amount } for the month: its own, or else the latest
  # earlier month's.
  def amounts
    source = initialized_budget || previous_budget
    return {} unless source

    source.budget_categories.reject(&:subcategory?).to_h { |row| [ row.category_id, row[:budgeted_spending].to_d ] }
  end

  # Gives a month without a budget the amounts of the latest earlier month
  # that has one. Returns the month's budget, or nil when there is nothing
  # to carry forward.
  def ensure!
    return initialized_budget if initialized_budget

    source = previous_budget
    return unless source

    budget = bootstrap(month)
    return unless budget

    budget.copy_from!(source)
    @initialized_budget = budget
  end

  # Sets the month's amounts ({ category_id => amount }) and those of the
  # later months already created.
  def save!(new_amounts)
    allowed = categories.map(&:id).to_set
    clean = new_amounts.to_h.transform_keys(&:to_s).select { |id, _| allowed.include?(id) }
                       .transform_values { |value| [ value.to_s.tr(",", ".").to_d, 0 ].max }

    Budget.transaction do
      budgets = [ bootstrap(month), *later_budgets ].compact.uniq
      budgets.each { |budget| apply(budget, clean) }
    end

    @initialized_budget = nil
    true
  end

  private
    def owner_scope
      family.budgets.where(user_id: bootstrap_owner_id)
    end

    # The owner the app gives the budgets it creates for this user (nobody,
    # the shared one, unless the family keeps personal budgets).
    def bootstrap_owner_id
      family.personal_budgets? ? user&.id : nil
    end

    def initialized_budget
      return @initialized_budget if defined?(@initialized_budget) && @initialized_budget

      @initialized_budget = owner_scope.where(start_date: period_start).where.not(budgeted_spending: nil).first
    end

    def previous_budget
      owner_scope.where(start_date: ...period_start).where.not(budgeted_spending: nil).order(start_date: :desc).first
    end

    def later_budgets
      owner_scope.where("start_date > ?", period_start).order(:start_date).to_a
    end

    def period_start
      Budget.period_for(month, family: family).first
    end

    def bootstrap(date)
      Budget.find_or_bootstrap(family, start_date: date, user: user, household: false)
    end

    def apply(budget, amounts)
      rows = budget.budget_categories.includes(:category).to_a
      rows.each do |row|
        amount = row.subcategory? ? 0 : amounts.fetch(row.category_id, row[:budgeted_spending].to_d)
        row.update!(budgeted_spending: amount) if row[:budgeted_spending].to_d != amount
      end

      budget.update!(budgeted_spending: rows.reject(&:subcategory?).sum { |row| row[:budgeted_spending].to_d },
                     expected_income: budget.expected_income || 0)
    end
end
