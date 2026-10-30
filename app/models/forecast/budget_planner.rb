# Fulas Bank: the budgets of the coming months worked out from the forecast,
# each month with its own amounts: for every main category, what it usually
# spends on variable things that month (the same trimmed mean as "Gastos
# varios", with the month plans and the categories left out in «Ver
# cálculo») plus the recurring payments it has that month (so an annual
# insurance raises its own month only). Rounded up to whole euros.
#
# From then on the budget rules: the forecast takes each category's budget
# minus its recurring payments (Forecast::BudgetSource).
class Forecast::BudgetPlanner
  MONTHS = 60

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

  # { main category id => amount } for `month`, positive amounts only.
  def amounts_for(month)
    expected = recurring.for(month)

    categories.each_with_object({}) do |category, result|
      id = category.id.to_s
      variable = if plan.excluded?(id)
        0.to_d
      else
        plan.plan_for(month, id)&.amount || estimate.category_monthly(month, id)
      end
      amount = (variable + expected.fetch(id, 0)).ceil
      result[id] = amount if amount.positive?
    end
  end

  # Writes every month. @return [Integer] the months written
  def apply!
    months.each do |month|
      amounts = amounts_for(month)
      MonthBudget.new(family, user: user, month: month)
                 .save_month!(categories.to_h { |category| [ category.id.to_s, amounts.fetch(category.id.to_s, 0) ] })
    end
    months.size
  end

  private
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
    def categories
      @categories ||= MonthBudget.new(family, user: user, month: today).categories
                                 .reject { |category| %w[income savings].include?(category.spending_class) }
    end
end
